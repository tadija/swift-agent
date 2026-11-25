#!/bin/sh
set -eu
source_directory=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir "$fixture/source"
(cd "$source_directory" && tar --exclude=.build --exclude=.git -cf - .) | (cd "$fixture/source" && tar --no-same-owner -xf -)
cd "$fixture/source"
# Redirect only this disposable upstream copy to its local trusted source.
swift - "$fixture/source" <<'SWIFT'
import Foundation
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let input = source.appendingPathComponent("Sources/swift-agent/agent.json")
var product = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as! [String: Any]
product["update"] = ["repository": source.absoluteString]
try JSONSerialization.data(withJSONObject: product, options: [.prettyPrinted, .sortedKeys]).write(to: input)
SWIFT
git init -q -b main
git add .
git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm Fixture
./Scripts/install.sh "$fixture/bin"
before=$("$fixture/bin/swift-agent" --version)
# This is the actual upstream entry point, generated metadata, CLI and updater.
"$fixture/bin/swift-agent" update > "$fixture/update"
grep -q 'Installed Swift Agent .*source ' "$fixture/update"
[ "$("$fixture/bin/swift-agent" --version)" = "$before" ]
sh Tests/Integration/generic-cli-smoke.sh "$fixture/bin/swift-agent"
sh Tests/Integration/cli-commands-smoke.sh "$fixture/bin/swift-agent"
printf 'Upstream source update smoke test passed\n'
