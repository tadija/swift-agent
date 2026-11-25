# Declarative agent products

Create a specialized agent with an executable entry point and required target-local `agent.json`
metadata plus an optional `prompt.md` mission. Neither input is runtime configuration or a bundled resource.

```text
Package.swift
Sources/doc-agent/
    main.swift
    prompt.md
    agent.json
```

## Complete package

Requires Swift 6.4+, macOS 13+ or Linux. After 0.2.0 is released, use:

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DocumentationAgent",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "doc-agent", targets: ["doc-agent"])],
    dependencies: [
        .package(url: "https://github.com/tadija/swift-agent.git", .upToNextMinor(from: "0.2.0"))
    ],
    targets: [
        .executableTarget(
            name: "doc-agent",
            dependencies: [
                .product(name: "SwiftAgent", package: "swift-agent"),
                .product(name: "SwiftAgentCLI", package: "swift-agent")
            ],
            exclude: ["prompt.md", "agent.json"],
            plugins: [
                .plugin(name: "AgentProductPlugin", package: "swift-agent")
            ]
        )
    ]
)
```

`exclude` suppresses SwiftPM's unhandled-file warnings; the plugin reads the named
paths directly. Do not declare these files as resources. During development use
`.package(name: "swift-agent", path: "/path/to/swift-agent")` instead of the remote
dependency.

`Sources/doc-agent/agent.json`:

```json
{
  "name": "Documentation Agent",
  "version": "1.0.0",
  "executableName": "doc-agent",
  "commitIdentity": "Documentation Agent <documentation@localhost>",
  "update": {"repository": "https://github.com/your-organization/doc-agent"}
}
```

`Sources/doc-agent/prompt.md`:

```markdown
# Documentation agent
Improve one missing or incorrect usage example.
Check examples against the implementation and preserve public behavior.
```

`Sources/doc-agent/main.swift`:

```swift
import SwiftAgent
import SwiftAgentCLI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

let product = EmbeddedProduct.metadata
let agent = AgentDefinition(
    name: product.name,
    executableName: product.executableName,
    mission: EmbeddedMission.prompt,
    commitIdentity: product.commitIdentity
)
let update = try product.update.map {
    try SourceUpdateConfiguration(repository: $0.repository, reference: $0.reference)
}
exit(AgentCLI.run(agent: agent, version: product.displayVersion, sourceUpdate: update))
```

The entry point maps plain generated metadata into CLI configuration. Adding or
removing `update` in JSON enables or disables the shared update command. The
generator has no runtime library dependency. See [source updates](SourceUpdates.md)
for installation policies and operational guarantees. Namespace and policy defaults
are configured through `AgentDefinition`.

```sh
swift build -c release --product doc-agent
# Copy the executable from `swift build -c release --show-bin-path` into your PATH.
doc-agent --version                         # Documentation Agent 1.0.0
cd /path/to/project
doc-agent run --harness codex
doc-agent run --prompt /path/to/other.md     # replaces the embedded default
```

Harness selection, schedules, checks, runtime mission paths and iteration settings
belong in `doc-agent.json` / global runtime configuration or CLI flags. See
[configuration](Configuration.md). `agent.json` is build-time identity, `prompt.md`
is the mission, and `main.swift` assembles the product. Repository/global mission
paths override the embedded mission; the execution contract always applies.

## Unified plugin and generated APIs

`AgentProductPlugin` is the public SwiftPM build-tool product. It always invokes
metadata generation from required target-local `agent.json`. When `prompt.md`
exists, it independently invokes mission generation. Each command declares its
own input, executable generator and Swift output in the plugin work directory.

| Input | Requirement | Generated API |
| --- | --- | --- |
| `agent.json` | Required | `EmbeddedProduct.metadata: EmbeddedProduct.Metadata` |
| `prompt.md` | Optional | `EmbeddedMission.prompt: String` |

Generated declarations are internal to the consuming target and depend only on
the Swift standard library. Metadata contains `name`, `version`, `executableName`
(`String`), `build` and `commitIdentity` (`String?`), optional `update: EmbeddedProduct.Update?`, and
computed `displayVersion`: `"name version"` or `"name version (build)"`.
Metadata has no mission, harness/session configuration, implicit Git lookup or machine path.

A product without an embedded mission uses the same plugin:

```swift
.executableTarget(name: "MetadataOnly", exclude: ["agent.json"], plugins: [
    .plugin(name: "AgentProductPlugin", package: "swift-agent")
])
```

Omit `prompt.md` and construct `AgentDefinition` without its `mission` argument.
No `EmbeddedMission` declaration is generated. SwiftAgent's generic executable
uses this mode and requires a runtime mission. A present but empty, blank or
invalid UTF-8 `prompt.md` is an error. Mission-only plugin targets are unsupported:
all plugin consumers must declare product metadata. Products that construct their
own definitions and pass mission/version strings directly can omit the plugin.

## BSA migration after 0.2.0

Leave BSA unchanged until SwiftAgent 0.2.0 is released. Then update its SwiftAgent
dependency to 0.2.0 and replace both previous plugin declarations with:

```swift
plugins: [
    .plugin(name: "AgentProductPlugin", package: "swift-agent")
]
```

Keep target-local `agent.json` and BSA's `prompt.md` excluded from resources and
unhandled-file scanning. Preserve the existing metadata schema, entry point,
`EmbeddedProduct.metadata`, `EmbeddedMission.prompt`, and source updater mapping.
If migrating a mission-only declaration, add required `agent.json` metadata.
Build and test BSA, then verify the installed executable outside its checkout.
The previous plugin names have no compatibility aliases.

## Metadata schema

The JSON object has three required fields and three optional fields. Unknown keys
are rejected to catch misspellings and accidental runtime settings.

| Field | Type | Meaning and validation |
| --- | --- | --- |
| `name` | String, required | Display name; nonblank, no control characters. Unicode, quotes and backslashes are preserved. |
| `version` | String, required | Semantic Version, including optional prerelease/build identifiers; no leading `v` or surrounding whitespace. |
| `build` | String or null, optional | Explicit build/provenance identifier, such as a commit ID or CI build number. Nonblank, no control characters; omission/null omits the display suffix. |
| `executableName` | String, required | CLI/config/namespace stem; ASCII letters, digits, hyphens and underscores, nonempty. |
| `commitIdentity` | String or null, optional | Default author and committer: `Name <email>` or `git`. Omission/null preserves the identity derived by `AgentDefinition`; control characters and malformed identities fail generation. |
| `update` | Object or null, optional | Trusted `repository` URL and optional `reference` (default `main`). Generated as plain data; no runtime dependency. |

For example, an explicit `"build": "5475660"` produces
`Swift Agent 0.2.0 (5475660)` while retaining `version == "0.2.0"` and
`build == "5475660"` as separate typed values. Build identifiers are supplied by
the caller, never discovered by the generator. In CI, this repository writes the
first seven characters of `GITHUB_SHA` into the runner's `agent.json` before the
release build; the checked-in declaration remains unstamped. Local builders may
set the field explicitly or leave it absent. No second version file or hidden
environment-variable input affects plugin output. The same explicit input always
produces the same source.

Release tooling should read the version from `agent.json` and tag the
corresponding commit. The name/executable values must agree with the
package's executable product and installer destination; SwiftPM cannot infer that
mapping for arbitrary targets. Pass generated `product.commitIdentity` to
`AgentDefinition(commitIdentity:)` as shown above. Repository/global runtime
`commitIdentity` settings and `--identity` still override that product default.
`build` records artifact provenance and has no effect on the author of agent commits.

## Implementation and build guarantees

`EmbedMissionGenerator` and `ProductMetadataGenerator` are executable tool targets.
Each is a standalone Foundation-only Swift source with no engine/CLI dependency.
The metadata parser, SemVer rules, renderer and writer have no knowledge of a
package, an agent mission, SwiftAgent APIs, or `agent.json`. The plugin alone
selects that conventional filename. The executable accepts explicit paths:

```sh
swift run --package-path /path/to/swift-agent ProductMetadataGenerator product.json /tmp/EmbeddedProduct.swift
swift run --package-path /path/to/swift-agent EmbedMissionGenerator mission.md /tmp/EmbeddedMission.swift
```

These tool targets are implementation details rather than a separately versioned
general-purpose tooling package. The fixed simple schema and generated type names
are intentionally small; arbitrary schema configuration is out of scope.

UTF-8 byte literals preserve Unicode, line endings, multiline Markdown, quotes,
backslashes and Swift interpolation syntax. Empty/blank or invalid UTF-8 missions
fail. JSON is decoded/validated before writing output. Identical inputs yield
identical source; unchanged output is not rewritten. No timestamp, Git subprocess,
network request, absolute source path or tracked generated file enters the output.
SwiftPM tracks each input and its executable generator, rerunning generation when
either changes. Missing metadata or invalid present inputs fail the build with diagnostics.
Adding or removing the optional mission changes the generated source set.

Installed executables need neither original input nor generated sources, checkout,
resource bundles, generators, Git metadata, or SwiftAgent installation. Git/project
toolchains and a harness remain requirements for running agent sessions. Builds
require a Swift toolchain and initial dependency resolution; a remote package
fetch naturally needs network unless cached.

## Schema evolution

Changing supported values in a product's `agent.json` requires rebuilding that
product, not releasing SwiftAgent. Adding keys or changing generation/validation
rules requires a SwiftAgent release before remote-package consumers can use them.
Use a local path dependency to test unreleased tooling. Keep published versions
immutable and resolve consumers to a release that supports their declared schema.
Unknown keys are intentionally rejected; arbitrary runtime configuration does not
belong in this build-time declaration.
