#!/bin/sh
set -eu
source_directory=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/Sources/DocumentationAgent"
cat > "$fixture/Package.swift" <<PACKAGE
// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "Consumer", platforms: [.macOS(.v13)], products: [.executable(name: "doc-agent", targets: ["DocumentationAgent"])], dependencies: [.package(name: "swift-agent", path: #"$source_directory"#)], targets: [
    .executableTarget(name: "DocumentationAgent", dependencies: [
        .product(name: "SwiftAgent", package: "swift-agent"),
        .product(name: "SwiftAgentCLI", package: "swift-agent")
    ], exclude: ["prompt.md", "agent.json"], plugins: [
        .plugin(name: "AgentProductPlugin", package: "swift-agent")
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
let product = EmbeddedProduct.metadata
let agent = AgentDefinition(name: product.name, executableName: product.executableName,
                            mission: EmbeddedMission.prompt, commitIdentity: product.commitIdentity)
let update = try product.update.map {
    try SourceUpdateConfiguration(repository: $0.repository, reference: $0.reference)
}
exit(AgentCLI.run(agent: agent, version: product.displayVersion, sourceUpdate: update))
SWIFT
printf '%s\n' 'Improve one usage example.' > "$fixture/Sources/DocumentationAgent/prompt.md"
printf '%s\n' '{"name":"Documentation Agent","version":"1.2.3","build":"fixture123","executableName":"doc-agent"}' > "$fixture/Sources/DocumentationAgent/agent.json"
swift build --package-path "$fixture" --product doc-agent
binary_directory=$(swift build --package-path "$fixture" --show-bin-path)
"$binary_directory/doc-agent" --help > "$fixture/without-update"
if grep -q 'update .*configured source' "$fixture/without-update"; then exit 1; fi
grep -q 'Documentation Agent <doc-agent@localhost>' "$fixture/without-update"
if "$binary_directory/doc-agent" update > "$fixture/unsupported-update" 2>&1; then exit 1; fi
grep -q 'Self-update is unavailable' "$fixture/unsupported-update"
# The entry point stays unchanged when optional metadata enables source updates.
printf '%s\n' '{"name":"Documentation Agent","version":"1.2.3","build":"fixture123","executableName":"doc-agent","commitIdentity":"Documentation Agent <documentation@localhost>","update":{"repository":"https://example.invalid/trusted-doc-agent"}}' > "$fixture/Sources/DocumentationAgent/agent.json"
swift build --package-path "$fixture" --product doc-agent
binary_directory=$(swift build --package-path "$fixture" --show-bin-path)
cp "$binary_directory/doc-agent" "$fixture/doc-agent"
"$fixture/doc-agent" --help > "$fixture/help"
grep -q 'Usage: doc-agent' "$fixture/help"
grep -q 'update .*configured source' "$fixture/help"
[ "$("$fixture/doc-agent" --version)" = 'Documentation Agent 1.2.3 (fixture123)' ]
# Installed operation must not read source inputs, generated files, or a build tree.
rm -rf "$fixture/.build" "$fixture/Sources"
mkdir "$fixture/project" "$fixture/bin"
cat > "$fixture/bin/documenter" <<'AGENT'
#!/bin/sh
case "$1" in *'Improve one usage example.'*|*'OVERRIDE_MISSION'*) ;; *) exit 2;; esac
if [ -n "${CONSUMER_PROMPT_CAPTURE:-}" ]; then printf '%s' "$1" > "$CONSUMER_PROMPT_CAPTURE"; fi
printf '%s\n' "${CONSUMER_DOCUMENTATION:-Documented usage}" > README.md
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
[ "$(git show -s --format='%an <%ae>|%s' doc-agent/project)" = 'Documentation Agent <documentation@localhost>|doc-agent: Document the usage example' ]
[ "$(cat README.md)" = Initial ]
"$fixture/doc-agent" run > "$fixture/noop"
grep -q no_candidate "$fixture/noop"
printf 'OVERRIDE_MISSION: inspect the documentation.\n' > "$fixture/override.md"
export CONSUMER_PROMPT_CAPTURE="$fixture/override-prompt"
"$fixture/doc-agent" run --prompt "$fixture/override.md" > "$fixture/override-run"
grep -q no_candidate "$fixture/override-run"
grep -q OVERRIDE_MISSION "$CONSUMER_PROMPT_CAPTURE"
if grep -q 'Improve one usage example.' "$CONSUMER_PROMPT_CAPTURE"; then exit 1; fi
grep -q 'Do not commit, push' "$CONSUMER_PROMPT_CAPTURE"
# Runtime CLI and configuration identities override the declarative product default.
CONSUMER_DOCUMENTATION='Use the Git identity' "$fixture/doc-agent" run --identity git > "$fixture/git-identity"
[ "$(git show -s --format='%an <%ae>' doc-agent/project)" = 'Fixture <fixture@example.invalid>' ]
printf '%s\n' '{"commitIdentity":"Configured Author <configured@example.invalid>","harness":"custom","customCommand":["documenter","{prompt}"],"verification":["test -s README.md"]}' > doc-agent.json
CONSUMER_DOCUMENTATION='Use the configured identity' "$fixture/doc-agent" run > "$fixture/config-identity"
[ "$(git show -s --format='%an <%ae>' doc-agent/project)" = 'Configured Author <configured@example.invalid>' ]
printf 'External package consumer smoke test passed\n'
