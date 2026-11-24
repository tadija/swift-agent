# SwiftAgent API and specialized agents

```text
swift-agent ─── SwiftAgentCLI ─── SwiftAgent ─── ProcessSupport (C)
your-agent ──── SwiftAgentCLI ─── SwiftAgent
```

`SwiftAgent` owns the repository lifecycle, harnesses, native Ollama tool loop,
processes, checks, commits, limits, history, recovery, and schedules. It depends
only on Foundation, platform facilities, and internal C process support.
`SwiftAgentCLI` owns parsing, terminal output, signal installation, and return
codes. Executables own process exit, mission embedding, metadata, and updates.
There is no dependency on a specialized application.

## Create a specialized executable

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocumentationAgent",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/tadija/swift-agent.git", .upToNextMinor(from: "0.1.0"))
    ],
    targets: [
        .executableTarget(name: "doc-agent", dependencies: [
            .product(name: "SwiftAgent", package: "swift-agent"),
            .product(name: "SwiftAgentCLI", package: "swift-agent")
        ])
    ]
)
```

In `Sources/doc-agent/main.swift`:

```swift
import SwiftAgent
import SwiftAgentCLI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

let agent = AgentDefinition(
    name: "Documentation Agent",
    executableName: "doc-agent",
    mission: "Improve one missing or incorrect usage example."
)
exit(AgentCLI.run(agent: agent))
```

The mission string can contain your Markdown verbatim. For a standalone binary,
embed it as a Swift constant at build time; the engine needs no resource bundle.
Alternatively omit `mission` and use `--prompt PATH` or a configured file.
`AgentCLI.run` accepts optional `arguments`, `version`, and an application-owned
`update` callback; it returns `Int32` and never exits the process itself.
No engine changes, subclass, or protocol implementation are needed for a new mission.

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

Use `Configuration(agent: agent)` for defaults without loading files. Passing a configuration is explicit: create/load it with the same agent to select its identity and stop defaults. `Runner.run` executes one iteration; `runSession` executes a bounded sequence. `Runner.prompt`, `status`, `history`, and `stop` expose the existing operational functions. `Record` and `Check` report results. `HarnessAdapter` permits deterministic custom implementations; `CommandHarness` and `Harnesses` provide reusable integrations, including the internal Ollama adapter. `CommandRunner`/`CommandResult` provide bounded subprocess execution. Errors use `AgentError`.

The public surface reuses the existing synchronous process/harness API. It does not introduce an async wrapper around blocking work. Cancellation remains cooperative through `Cancellation` and repository stop markers, with process-group termination and bounded grace periods. An explicit `dataDirectory` replaces the resolved state root; supply distinct roots for distinct agents when overriding it. Signal installation is opt-in for programmatic callers (`Cancellation.install()`). Cancellation state is process-wide: run one session at a time in an embedding process. Concurrent sessions within one process and task-local cancellation are not supported. A future concurrency redesign should address that state at its source.

Definitions contain a display name, executable name, optional Markdown mission, and optional commit identity, branch/state namespaces, and consecutive no-candidate limit. Executable and namespace components must be nonempty ASCII letters, digits, hyphens, or underscores. Defaults derive from the executable name; custom namespaces should be unique per agent. Explicit blank missions fail unless a prompt file replaces them. No generic mission is inferred. Avoid defining a protocol or subclass for a new mission.

## Distribution

The generic executable embeds its own `VERSION` and Git revision through the
`BuildVersion` plugin. Source archives report `unknown` for the revision.
Libraries do not generate mission or executable metadata. Installed binaries
require no source checkout or Markdown resource; explicit runtime mission files
remain caller-owned inputs. External harnesses and project toolchains remain
runtime requirements.
