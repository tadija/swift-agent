# Source updates

SwiftAgentCLI provides `SourceUpdateConfiguration` and `SourceUpdater` for
building and installing an executable from its trusted source repository.
Applications opt in through CLI configuration or call the updater directly.

## Opt in

Use the [minimal agent example](BuildTooling.md). Its optional declaration is:

```json
"update": {"repository": "https://github.com/your-organization/doc-agent"}
```

`repository` must be an absolute HTTPS, SSH or file URL. `reference` optionally
selects a branch, tag or commit; omission selects `main`.
Use `refs/heads/name` or `refs/tags/name` to disambiguate branches and tags. A commit
must be fetchable from the configured remote. There is no latest-release lookup,
SemVer ordering, implicit channel fallback or CLI override. `update` takes no
options. A source update can install an older version if its configured reference
points there; this is source selection, not a monotonic release policy.

Generated `EmbeddedProduct.Update` contains `repository` and `reference` strings.
It imports no runtime libraries. The minimal example explicitly maps it into
`SourceUpdateConfiguration`; adding JSON alone then enables the command. Omitted
or null `update` disables it and removes it from help. No mission is required.
Unknown nested keys and invalid URLs/references fail generation; programmatic
configuration applies the same basic validation. Git diagnoses invalid Git refs.

Without the plugin, configure the CLI directly:

```swift
let agent = AgentDefinition(name: "Documentation Agent", executableName: "doc-agent")
let update = try SourceUpdateConfiguration(
    repository: "https://github.com/your-organization/doc-agent",
    reference: "main"
)
let status = AgentCLI.run(agent: agent, version: "Documentation Agent 1.0.0",
                          sourceUpdate: update)
```

Or call `SourceUpdater(configuration: update, agent: agent).update(executable: url)`
directly. The CLI installs cancellation signal handlers; direct callers can use
`Cancellation.install()` and the `Cancellation` API when they own signal
handling. The executable/product name and validation display name derive from the
agent definition; there is no second identity configuration. The SwiftPM
executable product must have the same name as `agent.executableName`. Release is
the build configuration used for source updates.

`AgentCLI.run` exposes the update command when `sourceUpdate` is configured.
Products without this configuration have no update command in help and perform
no update network activity.

## Lifecycle and guarantees

1. Resolve the launched executable through symlinks. Require an existing regular
   executable and writable parent; reject setuid/setgid executables, SwiftPM build
   trees and known system/package-manager locations. No privilege elevation occurs.
2. Acquire a nonblocking advisory `flock` beside the resolved installation, keyed
   by destination filename. Another updater for that destination fails promptly.
   The hidden lock file stays in place to avoid an inode/unlink race; its OS lock
   releases on normal return or process death. Do not delete it during an update.
3. Create a private temporary directory. Clone only the configured source,
   explicitly fetch the configured reference, resolve `FETCH_HEAD` to a commit,
   and check out that commit detached. The user's repositories are never edited.
4. Run `swift build -c release --product <executableName>`, then ask SwiftPM for
   its binary path. Require an absolute single-line path and a nonempty regular
   executable artifact; reject symlinks and directories.
5. Copy into a unique sibling of the destination, retain its ordinary permission
   bits, and execute the staged artifact with `--version`. Require a successful,
   complete UTF-8, single-line response beginning with the exact display name
   and a nonempty version. This check does not prove that the artifact honestly
   reports its source or build identity.
6. Check cancellation and that the destination inode has not changed. POSIX
   `rename` replaces the destination atomically on its filesystem. A running Linux
   executable remains replaceable. Report the displayed version and Git revision.
7. Remove the temporary checkout and any uninstalled staged artifact on return.

Fetch, build, validation, cancellation and rename failures leave the updater's
installed executable untouched. Diagnostics include the failed command's bounded
output or the filesystem error. Subprocesses use argument arrays, never shell
interpolation. `CommandRunner` timeouts, process-group termination and
SIGINT/SIGTERM cancellation apply, including children spawned by builds. The
last cancellation check precedes rename: cancellation after commit cannot undo a
successful installation. SIGKILL, power loss or an unhandled fatal signal can
leave temporary/staged files for manual cleanup; the old or new executable stays
in place, and the OS releases the lock. Crash durability across power loss is not
promised (no file/directory fsync transaction).

## Installation and trust limits

Supported: source-installed or manually copied standalone executables in
user-controlled writable directories (the installer defaults to `~/.local/bin`).
Symlinks stay intact; the resolved executable is updated. Known Homebrew, MacPorts,
Nix, Snap and system executable locations are refused, as are `.build` paths.
Use their manager or rebuild/install command instead. Package-manager detection
is conservative and path-based, not an exhaustive package database query; do not
use source updates for managed installations in custom prefixes. Initial
installation remains `Scripts/install.sh`, not `update`.

Only configure explicitly trusted sources. Git operations and SwiftPM builds can
use the network, resolve dependencies and execute repository/plugin/build code.
Validation executes the candidate too. Neither identity output nor a Git hash is
a signature or a sandbox. The destination directory, source repository, toolchain,
Git configuration, dependencies and PATH must be trusted. Locks coordinate this
updater, not arbitrary installers or malicious filesystem writers. No background
updates or implicit network access occur during normal agent execution, help or
version commands. No automatic repository/channel switching or elevation occurs.
