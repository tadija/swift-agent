# SwiftAgent API and specialized agents

```text
swift-agent ─── SwiftAgentCLI ─── SwiftAgent ─── ProcessSupport (C)
your-agent ──── SwiftAgentCLI ─── SwiftAgent
```

`SwiftAgent` owns the repository lifecycle, harnesses, native Ollama tool loop,
processes, checks, commits, limits, history, recovery, and schedules. It depends
only on Foundation, platform facilities, and internal C process support.
`SwiftAgentCLI` owns parsing, terminal output, signal installation, return codes,
and source updates. Executables own process exit. `AgentProductPlugin` provides
embedded missions and typed product metadata.
There is no dependency on a specialized application.

## Create a specialized executable

Use the [complete declarative product guide](BuildTooling.md) for a three-file
agent, plugin manifests, schema, and generated APIs. Public package products
are `SwiftAgent`, `SwiftAgentCLI`,
`swift-agent`, and `AgentProductPlugin`.

The plugin is optional. A programmatic executable may construct
`AgentDefinition(name:executableName:mission:)` and pass it to `AgentCLI.run`.
`AgentCLI.run` accepts optional `arguments`, `version`, and
`sourceUpdate: SourceUpdateConfiguration?`. It returns `Int32` without exiting
the process.

## Programmatic execution

```swift
import Foundation
import SwiftAgent

let directory = URL(fileURLWithPath: "/path/to/repository")
let agent = AgentDefinition(name: "Documentation Agent", executableName: "doc-agent",
                            mission: "Improve one missing or incorrect usage example.")
var configuration = try Configuration.load(repository: Repository(at: directory), agent: agent)
configuration.maxIterations = 3
let harness = try Harnesses.select(configuration: configuration, directory: directory)
let records = try Runner(agent: agent).runSession(
    at: directory, configuration: configuration, harness: harness,
    onProgress: { print($0) }, onIteration: { print($0.outcome) })
```

Use `Configuration(agent: agent)` for defaults without loading files. Create or
load configuration with the same agent to apply its identity and stop defaults.
`Runner.run` executes one iteration; `runSession` executes a bounded sequence.
`Runner.prompt`, `status`, `history`, and `stop` provide repository operations.
`Record` and `Check` report results, including session identity, harness, outcome,
and phase timings.

Implement `HarnessAdapter` for a custom harness, or use `Harnesses` for built-in
CLI integrations and Ollama. `CommandRunner` and `CommandResult` provide bounded
subprocess execution. Errors use `AgentError`.

Process and harness APIs are synchronous. Cancellation is cooperative through
`Cancellation` and repository stop markers, with process-group termination and
bounded grace periods. Programmatic callers install signal handlers explicitly
with `Cancellation.install()`. Cancellation state is process-wide: run one session
at a time in an embedding process. Concurrent sessions within one process and
task-local cancellation are not supported.

An explicit `dataDirectory` replaces the resolved state root. Supply distinct
roots for distinct agents when overriding it.

Build-time `agent.json` may declare an optional `commitIdentity` product default.
Pass generated `EmbeddedProduct.metadata.commitIdentity` to `AgentDefinition`;
omission/null preserves the derived identity. Runtime configuration and `--identity`
retain their precedence. See [build tooling](BuildTooling.md) for validation.

Definitions contain a display name, executable name, optional Markdown mission,
and optional commit identity, branch/state namespaces, and consecutive
no-candidate limit. Executable and namespace components must be nonempty ASCII
letters, digits, hyphens, or underscores. Defaults derive from the executable
name; custom namespaces should be unique per agent. Explicit blank missions fail
unless a prompt file replaces them. A generic run requires an explicit mission.

## Distribution

The generic executable uses `AgentProductPlugin` and its target-local
`agent.json`. Specialized executables use the same plugin, with an optional
`prompt.md` mission.
Generated source contains declared name/version, optional build ID and product
identity, without Git lookups, paths or timestamps. `--version` prints `name version`
or `name version (build)` when explicitly stamped.
Libraries do not generate mission or executable metadata. Installed binaries
require no source checkout or Markdown resource; explicit runtime mission files
remain caller-owned inputs. External harnesses and project toolchains remain
runtime requirements. Supply the version display string through `AgentCLI.run`.

`SourceUpdateConfiguration(repository:reference:)` is a throwing initializer;
`reference` defaults to `main`. `SourceUpdater(configuration:agent:)` exposes
`update(executable:onProgress:)` for programmatic use without either plugin or an
embedded mission. Product/executable identity comes from `AgentDefinition`.
See [source updater lifecycle and trust boundary](SourceUpdates.md).
