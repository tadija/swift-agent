#!/bin/sh
set -eu
source_directory=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/Sources/DocumentationAgent"
cat > "$fixture/Package.swift" <<PACKAGE
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Consumer", platforms: [.macOS(.v13)], dependencies: [.package(name: "swift-agent", path: #"$source_directory"#)], targets: [
    .executableTarget(name: "DocumentationAgent", dependencies: [
        .product(name: "SwiftAgent", package: "swift-agent"),
        .product(name: "SwiftAgentCLI", package: "swift-agent")
    ])
])
PACKAGE
cat > "$fixture/Sources/DocumentationAgent/main.swift" <<'SWIFT'
import SwiftAgent
import SwiftAgentCLI
#if os(Linux)
import Glibc
#else
import Darwin
#endif
let agent = AgentDefinition(name: "Documentation Agent", executableName: "doc-agent",
                            mission: "Improve one usage example.")
exit(AgentCLI.run(agent: agent))
SWIFT
swift build --package-path "$fixture" --product DocumentationAgent
binary_directory=$(swift build --package-path "$fixture" --show-bin-path)
cp "$binary_directory/DocumentationAgent" "$fixture/doc-agent"
"$fixture/doc-agent" --help > "$fixture/help"
grep -q 'Usage: doc-agent' "$fixture/help"
if find "$fixture/.build" -name EmbeddedMission.swift | grep -q .; then exit 1; fi
mkdir "$fixture/project" "$fixture/bin"
cat > "$fixture/bin/documenter" <<'AGENT'
#!/bin/sh
case "$1" in *'Improve one usage example.'*) ;; *) exit 2;; esac
printf 'Documented usage\n' > README.md
printf 'Document the usage example\n'
AGENT
chmod +x "$fixture/bin/documenter"
export PATH="$fixture/bin:$PATH"
export XDG_CONFIG_HOME="$fixture/config"
export XDG_DATA_HOME="$fixture/state"
cd "$fixture/project"
git init -q -b main
git config user.name Fixture
git config user.email fixture@example.invalid
printf 'Initial\n' > README.md
printf '%s\n' '{"harness":"custom","customCommand":["documenter","{prompt}"],"verification":["test -s README.md"]}' > doc-agent.json
git add .
git commit -qm Initial
"$fixture/doc-agent" run > "$fixture/run"
grep -q 'committed on doc-agent/project' "$fixture/run"
[ "$(git show -s --format='%an <%ae>|%s' doc-agent/project)" = 'Documentation Agent <doc-agent@localhost>|doc-agent: Document the usage example' ]
[ "$(cat README.md)" = Initial ]
"$fixture/doc-agent" run > "$fixture/noop"
grep -q no_candidate "$fixture/noop"
printf 'External package consumer smoke test passed\n'
