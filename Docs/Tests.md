# Testing SwiftAgent

Requires Swift 6.4+, Git, and macOS or Linux.

```sh
SWIFT_AGENT_INTEGRATION_TESTS=1 swift test --parallel --num-workers 4
sh Tests/Integration/build-tool-smoke.sh
sh Tests/Integration/package-consumer-smoke.sh
sh Tests/Integration/source-update-smoke.sh
./Scripts/install.sh /tmp/swift-agent-bin
sh Tests/Integration/generic-cli-smoke.sh /tmp/swift-agent-bin/swift-agent
sh Tests/Integration/cli-commands-smoke.sh /tmp/swift-agent-bin/swift-agent
```

`swift test` skips the opt-in external Swift package fixture. The full command
above includes it. Tests use local Git repositories, temporary directories, fake
harnesses, simulated Ollama conversations, and mock HTTP transport. No live
models, paid APIs, installed agent CLIs, or Ollama server are needed.

## Library and CLI coverage

`SwiftAgentTests` covers Git isolation, ref integrity, process termination, limits,
checks, protected paths, prompts, configuration, history, recovery, scheduling,
harness selection, and Ollama tools. `SwiftAgentPublicTests` imports only the
public engine to verify independent product integration.
`HistoryCompatibilityTests` covers omitted/null legacy metadata, current-format
round trips, invalid records, status/history/prompt access, continued runs and
interruption recovery using existing history.

`HarnessSelectionTests` checks built-in argument mappings and detection in both
permission modes, including Ollama configuration. `cli-commands-smoke.sh` tests
actual process arguments, working directories, CLI/configuration precedence,
validation, and operational commands. `generic-cli-smoke.sh` covers explicit
missions, count/time flags, commits, history, schedules, and update help without
network access.

## Build tooling and consumers

`BuildToolTests` covers metadata validation (including optional commit identities), SemVer, mission encoding,
deterministic generation, and unchanged-output timestamps.
`build-tool-smoke.sh` builds targets with and without an embedded mission
without runtime dependencies. It tests input and generator-source rebuilds,
optional mission addition/removal, Unicode and escaping, missing/invalid inputs, arbitrary generator input filenames,
and I/O failures.

`package-consumer-smoke.sh` builds an independent package with `AgentProductPlugin`. It checks optional source update support, then installs the binary,
removes its inputs and build tree, and verifies an isolated documentation commit,
a no-op, runtime mission replacement, and runtime overrides of the declared commit identity.

## Source updates

`SourceUpdaterTests` covers configuration, revision selection, symlinks,
permissions, locks, failure preservation, invalid artifacts, validation and
replacement failures, cancellation, SIGTERM interruption, and resource cleanup.
Local tag, branch, and commit fixtures exercise real Swift release builds.

`source-update-smoke.sh` copies SwiftAgent into a disposable local Git repository,
points that copy's metadata to itself, installs it, and invokes the actual
`swift-agent update` command before the CLI smoke tests. It fetches no external
repository. Permission tests skip under privileged users; run them unprivileged
to exercise directory permission errors.

CI runs these checks on macOS and Linux, installs the release executable outside
the checkout, and packages it as a workflow artifact. Product-specific tests
belong in the consuming application's repository.
