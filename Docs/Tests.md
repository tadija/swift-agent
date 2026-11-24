# Testing SwiftAgent

```sh
SWIFT_AGENT_INTEGRATION_TESTS=1 swift test --parallel --num-workers 4
sh Tests/Integration/version-smoke.sh
sh Tests/Integration/package-consumer-smoke.sh
./Scripts/install.sh /tmp/swift-agent-bin
sh Tests/Integration/generic-cli-smoke.sh /tmp/swift-agent-bin/swift-agent
```

`swift test` runs core tests and skips the opt-in external Swift fixture build.
The full command above includes it. Tests use deterministic fake harnesses,
simulated Ollama conversations, and mock HTTP transport; no live models, paid
APIs, agent CLIs, or Ollama server are needed.

`SwiftAgentTests` owns Git isolation/ref guards, process termination, iteration
limits, checks, protected paths, prompts, configuration, history, recovery,
schedules, all harness mappings, and Ollama tools. A neutral definition with an
explicit fixture mission replaces the original application fixture.
`SwiftAgentPublicTests` imports only the public engine and proves another agent
can commit, stop on unchanged output, protect its config, and require a mission.

The generic CLI smoke test checks required/configured mission paths, count/time
flags, commits, history, schedules, and the explicit unsupported updater. The
consumer smoke test builds another Swift package against both libraries with
only a definition and CLI call, then installs that executable outside its build
tree and verifies a real isolated documentation commit and a subsequent no-op. Metadata tests cover archive fallback, ref-only
changes, branch switches, packed refs, worktrees, and unchanged generated output.

CI runs independently on macOS and Linux, installs the release executable outside
the checkout, and packages it as a workflow artifact. A clean-checkout build must
not depend on another source tree. Specialized application compatibility belongs
to its downstream repository. See [provenance](Provenance.md) for extraction and
release sequencing.
