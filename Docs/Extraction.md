# Independent package extraction report

## Baseline and ownership

Extraction starts from Boy Scout Agent `21c1fd6`, following its Stage 1 mechanism /
mission split (`1509eed`) and Stage 2 library/CLI boundaries (`b67443b`). All three
architectural plans, the Stage 2 completion report, manifest, source boundaries,
tests, specifications, scripts, and recent commits were reviewed. The engine and
CLI were already generic; test fixtures, tooling, documentation, and repository
ownership required separation.

The owner requested fresh upstream history. This repository therefore starts
with one initial commit containing the extracted source and documentation; no
BSA commits or refs are transferred. The original MIT notice is retained, and
[provenance](Provenance.md) identifies the source snapshot. BSA's history remains
unchanged.

`SwiftAgent` and internal `ProcessSupport` own all mechanism. `SwiftAgentCLI`
owns reusable commands. `swift-agent` supplies the generic definition and metadata.
No downstream import or dependency remains. The internal C spawn symbol/header
guard were renamed to neutral names; the public Swift API is unchanged.

The original mixed regression suite uses a neutral explicit fixture mission and
its own config/branch/state names. Shared behavior and specifications live only
upstream. Product mission/default/update tests stay downstream. Tiny build/version
and installer scripts are intentionally owned by each executable repository.
BSA's private metadata plugin was namespaced to avoid SwiftPM graph collisions.

## API and distribution

`AgentDefinition`, `Configuration`, `Repository`, `Runner`, `HarnessAdapter`,
`Harnesses`, `CommandRunner`, `CommandResult`, `Record`, `Check`, `Scheduler`,
`ExecutionWindow`, `Cancellation`, and `AgentError` retain their API. See [API](API.md)
for complete specialized CLI and programmatic examples. A definition containing
a name and Markdown mission plus optional configuration is sufficient; the
external-consumer test executes such an agent without modifying the package.

The independent installer builds a self-contained `swift-agent` executable and
atomically replaces it. External runtime prompts remain explicit caller inputs;
no generic default mission is invented. Updates use checkout + reinstall; the
application-owned updater hook is unchanged. Build metadata is independent from
BSA. macOS/Linux CI tests and packages this executable independently.

## Verification

- macOS arm64, Apple Swift 6.4.2: all **76** tests passed with external integration
  enabled, including a clean clone of local tag `0.1.0`.
- Linux arm64, Docker `swift:6.0-noble` / Swift 6.0.3: all **76** tests passed,
  including the external Swift fixture. Independent metadata smoke tests passed.
- Installed generic CLI smoke tests passed on both platforms: custom Markdown,
  required/configured prompt resolution, count/time bounds, commits/no-op,
  history, schedules, and unsupported self-update.
- Separate package consumer built and ran on both platforms, making an isolated,
  verified documentation commit and then a no-op with derived custom identity.
- Version/ref/archive/rebuild tests passed on both platforms. Clean macOS tag
  clone built and installed outside its checkout and passed CLI smoke tests.
- Downstream BSA validated all 7 product tests and full CLI/embedding/metadata
  smoke suites on both platforms against a temporary mirror of this tagged
  external package, without copying engine sources downstream.
- No live models, paid harnesses, GitHub CI runs, Intel platforms, or native
  system-service activation were tested. Linux checks ran in a container.

Linux's consumer check initially exposed a fixture assumption about checkout
basename; explicit local package naming fixed it. The downstream graph initially
exposed duplicate metadata plugin names; BSA now owns `BSABuildVersion`.
No engine behavior was rewritten to achieve extraction.

## Repository and release status

Public repository `https://github.com/tadija/swift-agent` was created with explicit
owner authorization and matches BSA's public visibility. Origin is its intended
SSH URL. The initial package and annotated `0.1.0` tag are published.

The owner subsequently authorized amending the initial commit, moving the example
mission to `Docs/Examples/PROMPT.md`, recreating `0.1.0`, and force-pushing the
updated branch and tag. The engine and public API remain unchanged. The original
local-only publication boundary above describes the initial validation run;
this follow-up uses direct GitHub resolution for downstream validation.

Tag **`0.1.0`** identifies the amended initial extraction commit. `VERSION` remains
`0.1.0`. BSA uses the remote URL with `upToNextMinor(from: "0.1.0")`, allowing
`0.1.x` and excluding breaking `0.2.0` updates. Its real `Package.resolved` must
record the recreated tag's revision. No machine-specific paths, mirrors, or
unpublished revision requirements are committed. Generic self-update remains
intentionally unsupported; checkout + reinstall is its update workflow.
