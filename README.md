# SwiftAgent

A harness-agnostic Swift framework for autonomous, iterative repository agents.

Give an agent a name, a Markdown mission, and optional configuration. SwiftAgent
handles isolated Git worktrees, harness execution, verification, commits, history,
limits, cancellation, and scheduling.

## Install

Requires Swift 6+, Git, and macOS or Linux. Install and authenticate Codex,
Claude Code, Pi, OpenCode, or Gemini; alternatively use a configured Ollama server.

```sh
git clone https://github.com/tadija/swift-agent.git
cd swift-agent
./Scripts/install.sh
export PATH="$HOME/.local/bin:$PATH"
swift-agent --version
```

Pass a destination to install elsewhere: `./Scripts/install.sh /path/to/bin`.
Update your checkout and rerun the installer to upgrade. Replacement is atomic
after a successful release build. The executable embeds its version and revision;
it needs no checkout or resource bundle at runtime. Self-update is not provided.

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

Depend on the `SwiftAgent` and `SwiftAgentCLI` products from this package:

```swift
.package(url: "https://github.com/tadija/swift-agent.git", .upToNextMinor(from: "0.1.0"))
```

A specialized executable supplies its definition and uses the shared CLI:

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

Or call the engine directly:

```swift
let repository = try Repository(at: directory)
var config = try Configuration.load(repository: repository, agent: agent)
config.maxIterations = 3
let harness = try Harnesses.select(configuration: config, directory: directory)
let records = try Runner(agent: agent).runSession(
    at: directory, configuration: config, harness: harness
)
```

[API and package integration](Docs/API.md) includes a complete manifest, metadata
and mission embedding guidance, public types, and cancellation limitations.

## Architecture and development

`SwiftAgent` owns the engine and internal C process support. `SwiftAgentCLI` owns
argument parsing and terminal output. `swift-agent` is the generic executable.
Applications supply mission, identity, defaults, metadata, and optional updates.
The engine has no dependency on a specialized application or external Swift package.

- [Specification](Docs/Specs.md) — execution and publication guarantees.
- [Testing](Docs/Tests.md) — independent tests and distribution checks.
- [Provenance and releases](Docs/Provenance.md) — history, versioning, publication sequence.

Version `0.1.0` is the initial independent package release. See the provenance
and release guide for versioning and downstream dependency conventions.
