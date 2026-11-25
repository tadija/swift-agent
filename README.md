# SwiftAgent

A Swift package for building autonomous, iterative repository agents.

Give an agent a name, a Markdown mission, and optional configuration. SwiftAgent
handles isolated Git worktrees, harness execution, verification, commits, history,
limits, cancellation, and scheduling.

## Install

Requires Swift 6.4+, Git, and macOS 13+ or Linux. Install and authenticate Codex,
Claude Code, Pi, OpenCode, or Gemini; alternatively use a configured Ollama server.

```sh
git clone https://github.com/tadija/swift-agent.git
cd swift-agent
./Scripts/install.sh
export PATH="$HOME/.local/bin:$PATH"
swift-agent --version
```

The installer defaults to `~/.local/bin`. Pass another destination with
`./Scripts/install.sh /path/to/bin`. Installed executables embed their product
metadata and need no source checkout or resource bundle.

Run `swift-agent update` to build and atomically install the configured `main`
source, or update your checkout and rerun the installer. Source updates require
Git and Swift and execute code from the trusted repository. See
[source updates](Docs/SourceUpdates.md) for installation policies and safeguards.

## Run a Markdown mission

```sh
cat > /tmp/documentation.md <<'MISSION'
# Documentation agent
Improve one missing or incorrect usage example.
Check examples against the implementation and preserve public behavior.
MISSION

cd ~/Projects/my-app
swift-agent run --prompt /tmp/documentation.md --count 3 --harness codex
swift-agent status
git diff HEAD...swift-agent/my-app
```

Each accepted change becomes one local commit on the printed branch. Your local
edits stay in your checkout. Merge or push after review. Each iteration starts a
fresh agent; count/time limits are maxima and repeated empty or failed attempts
stop early. No default mission is embedded in the generic executable.

Swift packages use `swift test`. Other projects need `swift-agent.json`, for example:

```json
{
  "prompt": "missions/documentation.md",
  "verification": ["python3 -m unittest discover -s tests"],
  "maxIterations": 3
}
```

```sh
swift-agent run --duration 1h
swift-agent config --prompt
swift-agent history
swift-agent stop
```

Use [the documentation mission](Docs/Examples/PROMPT.md) as a starting point.
[Configuration](Docs/Configuration.md) covers Rust/TypeScript checks, supported
harnesses, native Ollama, custom commands, permissions, identities, and defaults.
[Operations](Docs/Operations.md) covers schedules, recovery, and branch adoption.
Agent tools and checks run with your account's privileges; use trusted projects
or an OS sandbox. Worktrees are Git isolation, not a security sandbox.

## Create a custom agent

Define a product with required target-local `agent.json` metadata and an optional
`prompt.md` mission. `AgentProductPlugin` compiles these inputs into the executable:

```text
Sources/doc-agent/
    main.swift
    prompt.md
    agent.json
```

```json
{"name":"Documentation Agent","version":"1.0.0","executableName":"doc-agent"}
```

Apply the build tool to your executable target:

```swift
plugins: [
    .plugin(name: "AgentProductPlugin", package: "swift-agent")
]
```

The entry point assembles the product and uses the shared CLI:

```swift
import SwiftAgent
import SwiftAgentCLI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

let product = EmbeddedProduct.metadata
let agent = AgentDefinition(name: product.name, executableName: product.executableName,
                            mission: EmbeddedMission.prompt)
let update = try product.update.map {
    try SourceUpdateConfiguration(repository: $0.repository, reference: $0.reference)
}
exit(AgentCLI.run(agent: agent, version: product.displayVersion, sourceUpdate: update))
```

[Declarative products and build tooling](Docs/BuildTooling.md) provides the complete
manifest, input schema, plugin examples, and installation instructions.
Add an optional `update` repository to `agent.json` to enable the shared update
command; the entry point above handles either case. The metadata and mission
generators remain independent of each other and the runtime engine.
The generic executable uses metadata alone and supplies no artificial mission.
The plugin is optional; products can construct `AgentDefinition` directly.

For direct engine integration, see [API and package integration](Docs/API.md).

## Architecture and development

`SwiftAgent` owns the engine and internal C process support. `SwiftAgentCLI` owns
argument parsing, terminal output, and source updates. `swift-agent` is the generic
executable.
Applications supply mission, identity, defaults, metadata, and optional updates.
The engine has no dependency on a specialized application or external Swift package.

- [Specification](Docs/Specs.md) — execution and publication guarantees.
- [Testing](Docs/Tests.md) — library, CLI, build tooling, and consumer checks.

---

`done for fun`
