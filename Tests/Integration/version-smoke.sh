#!/bin/sh
set -eu
source_directory=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/source/Plugins" "$fixture/source/Scripts" "$fixture/source/Sources/Fixture"
cp -R "$source_directory/Plugins/BuildVersion" "$fixture/source/Plugins/"
cp "$source_directory/Scripts/build-metadata.swift" "$fixture/source/Scripts/"
cat > "$fixture/source/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VersionFixture", targets: [
    .executableTarget(name: "Fixture", plugins: ["BuildVersion"]),
    .plugin(name: "BuildVersion", capability: .buildTool())
])
PACKAGE
printf 'print(BuildVersion.display)\n' > "$fixture/source/Sources/Fixture/main.swift"
printf '0.2.1\n' > "$fixture/source/VERSION"
printf '.build/\n' > "$fixture/source/.gitignore"
git -C "$fixture/source" init -q
git -C "$fixture/source" config user.name 'SwiftAgent Test'
git -C "$fixture/source" config user.email 'fixture@example.invalid'
git -C "$fixture/source" add .
git -C "$fixture/source" commit -qm Initial
check_build() {
  swift build --package-path "$1" --product Fixture
  binary_directory=$(swift build --package-path "$1" --show-bin-path)
  revision=$(git -C "$1" rev-parse HEAD | cut -c1-7)
  [ "$("$binary_directory/Fixture")" = "Swift Agent $(cat "$1/VERSION") ($revision)" ]
}
check_build "$fixture/source"
# Ref-only changes must rebuild metadata even with unchanged package sources.
git -C "$fixture/source" commit --allow-empty -qm 'New build'
check_build "$fixture/source"
printf '0.2.2\n' > "$fixture/source/VERSION"
check_build "$fixture/source"
# Branch switches and packed refs must also invalidate metadata.
git -C "$fixture/source" checkout -qb metadata-fixture
git -C "$fixture/source" commit --allow-empty -qm 'Branch build'
check_build "$fixture/source"
git -C "$fixture/source" pack-refs --all
check_build "$fixture/source"
git -C "$fixture/source" commit --allow-empty -qm 'Build after packing refs'
check_build "$fixture/source"
# Unchanged metadata must not rewrite the generated source.
output="$fixture/output"
swift "$source_directory/Scripts/build-metadata.swift" "$fixture/source" "$output"
touch -t 202001010000 "$output/Generated/BuildVersion.swift"
cp -p "$output/Generated/BuildVersion.swift" "$fixture/previous"
swift "$source_directory/Scripts/build-metadata.swift" "$fixture/source" "$output"
[ ! "$output/Generated/BuildVersion.swift" -nt "$fixture/previous" ]
# Linked worktrees have a .git file rather than a directory.
git -C "$fixture/source" worktree add -q --detach "$fixture/worktree" HEAD
check_build "$fixture/worktree"
git -C "$fixture/worktree" commit --allow-empty -qm 'Detached worktree build'
check_build "$fixture/worktree"
# A nested archive must not borrow its enclosing repository's revision.
mkdir "$fixture/source/archive"
printf '0.2.1\n' > "$fixture/source/archive/VERSION"
swift "$source_directory/Scripts/build-metadata.swift" "$fixture/source/archive" "$output"
grep -q 'static let build = "unknown"' "$output/Generated/BuildVersion.swift"
printf 'invalid version\n' > "$fixture/source/archive/VERSION"
if swift "$source_directory/Scripts/build-metadata.swift" "$fixture/source/archive" "$output" > "$fixture/error" 2>&1; then exit 1; fi
grep -q 'VERSION must contain a Semantic Version' "$fixture/error"
printf 'Version smoke test passed\n'
