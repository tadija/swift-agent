#!/bin/sh
set -eu
source_directory=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
# An archive copy has no Git metadata and lets us test tool-source changes safely.
mkdir "$fixture/Tooling"
(cd "$source_directory" && tar --exclude=.build --exclude=.git -cf - .) | (cd "$fixture/Tooling" && tar -xf -)
mkdir -p "$fixture/Consumer/Sources/WithMission" "$fixture/Consumer/Sources/MetadataOnly"
cat > "$fixture/Consumer/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "PluginConsumer", platforms: [.macOS(.v13)], dependencies: [
    .package(name: "swift-agent", path: "../Tooling")
], targets: [
    .executableTarget(name: "WithMission", exclude: ["prompt.md", "agent.json"], plugins: [
        .plugin(name: "AgentProductPlugin", package: "swift-agent")
    ]),
    .executableTarget(name: "MetadataOnly", exclude: ["agent.json"], plugins: [
        .plugin(name: "AgentProductPlugin", package: "swift-agent")
    ])
])
PACKAGE
cat > "$fixture/Consumer/Sources/WithMission/main.swift" <<'SWIFT'
import Foundation
FileHandle.standardOutput.write(Data(EmbeddedMission.prompt.utf8))
SWIFT
cat > "$fixture/Consumer/Sources/WithMission/prompt.md" <<'MARKDOWN'
# Mission: café 🏕️
Preserve "quotes", \slashes, \(interpolation), {prompt}, $HOME and `literal`.

Multiline Markdown ends with a newline.
MARKDOWN
cat > "$fixture/Consumer/Sources/MetadataOnly/main.swift" <<'SWIFT'
let product = EmbeddedProduct.metadata
print(product.displayVersion)
print(product.executableName)
print(product.build ?? "unstamped")
print(product.update?.reference ?? "disabled")
SWIFT
printf '%s\n' '{"name":"Mission Fixture","version":"1.0.0","executableName":"mission-tool"}' > "$fixture/Consumer/Sources/WithMission/agent.json"
cat > "$fixture/Consumer/Sources/MetadataOnly/agent.json" <<'JSON'
{"name":"Café 🏕️ \"quotes\" \\slash","version":"1.2.3-rc.1+build.2","executableName":"fixture-tool","update":{"repository":"https://example.invalid/trusted"}}
JSON
cat > "$fixture/expected-product" <<'TEXT'
Café 🏕️ "quotes" \slash 1.2.3-rc.1+build.2
fixture-tool
unstamped
main
TEXT
cd "$fixture/Consumer"
swift build --product WithMission
swift build --product MetadataOnly
binary_directory=$(swift build --show-bin-path)
"$binary_directory/WithMission" > "$fixture/mission"
cmp Sources/WithMission/prompt.md "$fixture/mission"
"$binary_directory/MetadataOnly" > "$fixture/product"
cmp "$fixture/expected-product" "$fixture/product"
# Incremental builds must incorporate changes to either input independently.
printf '\nChanged mission input.\n' >> Sources/WithMission/prompt.md
swift build --product WithMission
"$binary_directory/WithMission" > "$fixture/mission"
cmp Sources/WithMission/prompt.md "$fixture/mission"
sed 's/1.2.3-rc.1+build.2/2.0.0/;s/"executableName"/"build":"build.123","executableName"/' Sources/MetadataOnly/agent.json > "$fixture/metadata"
mv "$fixture/metadata" Sources/MetadataOnly/agent.json
swift build --product MetadataOnly
"$binary_directory/MetadataOnly" > "$fixture/product"
grep -Fq '2.0.0 (build.123)' "$fixture/product"
# Generated files must remain byte-identical across a no-op build.
mission_source=$(find .build -name EmbeddedMission.swift -print -quit)
product_source=$(find .build -name EmbeddedProduct.swift -print -quit)
cp "$mission_source" "$fixture/previous-mission.swift"
cp "$product_source" "$fixture/previous-product.swift"
swift build
cmp "$mission_source" "$fixture/previous-mission.swift"
cmp "$product_source" "$fixture/previous-product.swift"
# SwiftPM must rebuild the executable tool and rerun generation after source edits.
sed 's/Generated mission/Regenerated mission/' "$fixture/Tooling/Sources/EmbedMissionGenerator/main.swift" > "$fixture/generator"
mv "$fixture/generator" "$fixture/Tooling/Sources/EmbedMissionGenerator/main.swift"
sed 's/Generated product metadata/Regenerated product metadata/' "$fixture/Tooling/Sources/ProductMetadataGenerator/main.swift" > "$fixture/generator"
mv "$fixture/generator" "$fixture/Tooling/Sources/ProductMetadataGenerator/main.swift"
swift build
grep -q 'Regenerated mission' "$mission_source"
grep -q 'Regenerated product metadata' "$product_source"
# Install outside the build tree, remove all inputs, and run independently.
cp "$binary_directory/WithMission" "$fixture/mission-tool"
cp "$binary_directory/MetadataOnly" "$fixture/metadata-tool"
mv Sources/WithMission/prompt.md "$fixture/expected-mission"
mv Sources/MetadataOnly/agent.json "$fixture/saved-metadata"
(cd / && "$fixture/mission-tool") > "$fixture/mission"
(cd / && "$fixture/metadata-tool") > "$fixture/product"
cmp "$fixture/expected-mission" "$fixture/mission"
grep -Fq '2.0.0 (build.123)' "$fixture/product"
# Removing an optional mission must remove its generated API from compilation.
mv "$fixture/saved-metadata" Sources/MetadataOnly/agent.json
printf 'print(EmbeddedProduct.metadata.name)\n' > Sources/WithMission/main.swift
swift build --product WithMission
"$binary_directory/WithMission" | grep -q 'Mission Fixture'
# A stale generated mission must not remain available after removal.
printf 'print(EmbeddedMission.prompt)\n' > Sources/WithMission/main.swift
if swift build --product WithMission > "$fixture/absent-mission" 2>&1; then exit 1; fi
grep -q 'cannot find.*EmbeddedMission' "$fixture/absent-mission"
mv "$fixture/expected-mission" Sources/WithMission/prompt.md
swift build --product WithMission
# Required metadata fails clearly even when the mission is present.
for target in WithMission MetadataOnly; do
    mv "Sources/$target/agent.json" "$fixture/saved-metadata"
    if swift build --product "$target" > "$fixture/missing" 2>&1; then exit 1; fi
    grep -q 'AgentProductPlugin requires agent.json' "$fixture/missing"
    mv "$fixture/saved-metadata" "Sources/$target/agent.json"
done
# Malformed inputs fail in generation and cannot overwrite prior valid output.
cp "$mission_source" "$fixture/valid-mission.swift"
cp "$product_source" "$fixture/valid-product.swift"
: > Sources/WithMission/prompt.md
if swift build --product WithMission > "$fixture/invalid" 2>&1; then exit 1; fi
grep -q 'Mission must be nonempty UTF-8 Markdown' "$fixture/invalid"
cmp "$mission_source" "$fixture/valid-mission.swift"
printf 'valid mission\n' > Sources/WithMission/prompt.md
printf '%s\n' '{"name":"Fixture","version":"invalid","executableName":"fixture"}' > Sources/MetadataOnly/agent.json
if swift build --product MetadataOnly > "$fixture/invalid" 2>&1; then exit 1; fi
grep -q 'version must be a Semantic Version' "$fixture/invalid"
cmp "$product_source" "$fixture/valid-product.swift"
# The metadata generator accepts arbitrary filenames, without the plugin/engine.
swift build --package-path "$fixture/Tooling" --product ProductMetadataGenerator
tool_directory=$(swift build --package-path "$fixture/Tooling" --show-bin-path)
printf '%s\n' '{"name":"Standalone","version":"1.0.0","executableName":"standalone"}' > "$fixture/product.json"
"$tool_directory/ProductMetadataGenerator" "$fixture/product.json" "$fixture/Standalone.swift"
grep -q 'enum EmbeddedProduct' "$fixture/Standalone.swift"
if "$tool_directory/ProductMetadataGenerator" "$fixture/missing.json" "$fixture/Standalone.swift" > "$fixture/io-error" 2>&1; then exit 1; fi
grep -q ProductMetadataGenerator "$fixture/io-error"
# Failed output writes also produce a clean diagnostic and nonzero status.
if "$tool_directory/ProductMetadataGenerator" "$fixture/product.json" /dev/null/output.swift > "$fixture/io-error" 2>&1; then exit 1; fi
grep -q ProductMetadataGenerator "$fixture/io-error"
printf 'Agent product build tool smoke test passed\n'
