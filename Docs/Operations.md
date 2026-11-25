# Running and maintaining SwiftAgent

## Inspect a run

Use `swift-agent status` for the latest outcome, branch, commit candidate and diagnostics. Per-iteration JSON records live under `$XDG_DATA_HOME/swift-agent` (default `~/.local/share/swift-agent`). After an interrupted publication, inspect the record and Git branch before attempting recovery.

Worktrees isolate proposed edits. Harnesses and verification commands still run with your account's permissions. Use trusted projects and commands, or run SwiftAgent in an OS sandbox.

Each iteration starts a fresh agent with recent tasks, failures and changed paths from the target branch. SwiftAgent stops after two consecutive empty attempts, three consecutive failures, cancellation, timeout, or an error that needs attention. Running again continues from the SwiftAgent branch. If your development branch has diverged, start a new target with `swift-agent run --branch swift-agent/next-improvement`, or explicitly continue from the existing target tip with `--force` (see recovery below).

## Overnight operation

```sh
swift-agent run --count 100 --until 04:00
swift-agent run --count 100 --duration 4h
swift-agent stop
swift-agent history
swift-agent doctor
```

Time windows cap active work as well as iteration starts; the smaller of the
iteration timeout and remaining window applies. Cleanup and process termination
may take additional time. `--until` uses the next local HH:MM, advancing missing
DST times and choosing the first repeated time. Use one window flag per run.
A window does not change the default one-iteration count; supply `--count` for
repeated work. SIGINT, SIGTERM and `stop` terminate process groups with a bounded
TERM grace period before KILL. Repository locks cover all branches and linked
worktrees, including runs using different data directories; kernel locks release
on process exit and require no stale PID deletion.

Cost budgets are unavailable because the adapters do not expose reliable normalized cost data. Use count and time bounds.

## Recurring schedules

```sh
swift-agent schedule add --at 00:00 --duration 4h
swift-agent schedule list
```

Definitions and executable wrappers live in `$XDG_DATA_HOME/swift-agent/schedules`.
Creation prepares files without enabling a service. The wrapper captures the
repository and executable paths, honors the configured `maxIterations` (default 1) and uses the current
repository configuration at execution time. Keep the installed SwiftAgent executable at
a stable absolute path. Native services need the harness executable on their PATH
and existing noninteractive authentication. Test the generated `.sh` manually
before enabling overnight execution.

On macOS, enable the generated plist with:

```sh
launchctl bootstrap "gui/$(id -u)" /absolute/path/to/ID.plist
# Disable before removing:
launchctl bootout "gui/$(id -u)" /absolute/path/to/ID.plist
```

On Linux, copy the generated `swift-agent-ID.service` and `swift-agent-ID.timer` into
`~/.config/systemd/user`, then:

```sh
systemctl --user daemon-reload
systemctl --user enable --now swift-agent-ID.timer
# Disable before removing:
systemctl --user disable --now swift-agent-ID.timer
```

After disabling, use `swift-agent schedule remove ID` to delete the definition and wrapper.
Where no user service manager is available, run the wrapper from your existing
scheduler. Schedules use host local time; the creation timezone is recorded for
reference. Native launchd/systemd DST and sleeping-host behavior applies; missed
runs are not explicitly replayed. Concurrent invocations fail safely on the
repository lock. User services require a logged-in user (or systemd lingering).

## Recovery and troubleshooting

After a crash, the next run acquires the repository lock and reconciles the latest
running record. If its candidate SHA equals the target ref, it records the commit
and restores branch ownership; otherwise it marks the attempt interrupted.
Unpublished candidates are never automatically published. Abandoned worktrees
remain in the repository's data directory for inspection and copying partial work.
Use `git worktree list`, inspect the relevant `worktree-ID` / `verify-ID`, then
remove them manually with `git worktree remove` when their contents are no longer
needed. Never delete the data directory to bypass branch ownership checks.

To explicitly adopt an existing or externally changed target branch, use:

```sh
swift-agent run --harness claude --branch swift-agent/my-project --force
```

`--force` continues from the target's current tip, including when it has diverged
from the configured base. It preserves existing commits and does not reset the
branch to the base. Adoption updates SwiftAgent's local ownership record, even if the
agent finds no candidate. A diverged target still needs `--force` on subsequent
runs, or a compatible `--base`. The target must be unchecked out in every worktree;
concurrent ref changes are still rejected. This flag applies only to this run and
cannot be enabled through `swift-agent.json`.

Normal rejected attempts discard their isolated
changes after saving bounded diagnostics, as required by the verification contract.

History JSON records retain bounded harness summaries and check outputs, IDs,
SHAs, paths and timings. Records are retained indefinitely for audit; native
schedule output logs should be rotated by the operator. They may contain sensitive
repository output. Older records remain readable without rewriting stored files:
missing or null session IDs use the record ID, harness names use `unknown`,
terminal flags use `false`, and phase timings use an empty dictionary. Invalid
field types and missing required record identity/outcome fields still fail decoding.
No dashboard, database or background SwiftAgent daemon is required.

Cancellation and timeout preserve dirty implementation worktrees. The iteration
record includes the path when Git refuses to remove one.

## Multiple specialized agents

Locks and stop markers use the agent's state namespace inside Git's common
directory. Linked worktrees and alternate data directories cannot bypass the
same-agent lock. Different agents have separate history and cancellation files;
run them sequentially against one repository because concurrent publication can
fail ref-integrity guards.

`swift-agent update` builds the configured trusted source and atomically replaces
the installed executable. It is available to specialized products through optional
CLI source update configuration. See [source updates](SourceUpdates.md) for source
selection, managed installation restrictions, cancellation and failure guarantees.
Updating a checkout and rerunning `./Scripts/install.sh` also remains supported.
