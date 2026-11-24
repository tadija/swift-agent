# Repository agent engine and CLI specification

SwiftAgent is a harness-agnostic Swift framework for autonomous, iterative
repository agents. It supplies mechanism; each application supplies its mission.
The engine is independent of CLI parsing and particular applications.

## Iteration contract

1. Validate configuration and resolve the session's Markdown mission.
2. Acquire the agent's repository lock across linked worktrees and data roots.
3. Reconcile interrupted history with the target ref; never publish abandoned candidates.
4. Resolve the base and owned, unchecked-out target branch. Reject unexpected
   divergence or external changes unless explicitly adopted with `--force`.
5. Create an isolated detached worktree and capture baseline check results.
6. Invoke a fresh harness with the execution contract, mission, guidance, and
   bounded branch history. The harness must not commit, push, or change refs.
7. Stage and inspect the candidate. Enforce protected paths, file/diff limits,
   binary/symlink/submodule restrictions, secret heuristics, and ref integrity.
8. Run final verification on the exact proposed tree in another fresh worktree.
   Checks must succeed and leave that tree unchanged. Harness build artifacts
   are not shared with final verification.
9. Create at most one commit and atomically advance the target with its expected
   prior ref. Publish no empty, rejected, failed, cancelled, or timed-out candidate.
10. Persist outcomes, paths, checks, timings, diagnostics, and commit provenance.

The user's checkout and index remain unchanged. Push is explicit, non-forced,
and application configuration controlled. `--force` adopts a tip without resetting
history and never bypasses checked-out-target or concurrent-ref guards.

## Sessions and operations

Count, per-iteration timeout, duration/local deadline, consecutive failure, and
consecutive no-candidate bounds stop work. Cancellation terminates process groups
with a bounded TERM grace period followed by KILL. Dirty implementation worktrees
are preserved on cancellation/timeouts; interrupted candidates require inspection.
A fresh harness starts each iteration. Reliable normalized monetary budgets are
unavailable. Scheduling generates wrappers and native service definitions without
enabling them. History uses atomic JSON files and requires no daemon or database.

Outcomes: `committed`, `no_candidate`, `rejected`, `verification_failed`,
`harness_failed`, `timed_out`, `cancelled`, `interrupted`.

## Mission and security boundary

Definitions provide name, executable, optional mission, commit identity, namespaces,
and no-candidate limit. CLI prompt > repository prompt > global prompt > definition
mission. A generic run requires an explicit mission; blank/invalid files fail.
The engine contract cannot be overridden by mission or project instructions.

Worktrees isolate Git contents, not account privileges. Harnesses, Ollama shell
tools, and checks can execute arbitrary commands. Use trusted projects or an OS
sandbox. Protected paths and diff heuristics are conservative mechanical checks,
not proof of semantic correctness or a filesystem sandbox.

## Public surface and implementation constraints

[API](API.md) defines library integration and process-wide cooperative cancellation
limitations. The synchronous public API is preserved. Run one session per embedding
process; run different agent processes sequentially against one repository.
[Configuration](Configuration.md) owns the shared schema and harness mappings.
[Operations](Operations.md) owns deadlines, scheduling, recovery, and retention.
The CLI exposes init, run, config, status, history, stop, doctor, harnesses,
schedule, and an optional application-owned update action.

macOS 13+ and Linux use Swift 6+ with no external package dependencies. No hosted
services, universal workflow framework, multi-agent orchestration, or GUI are part
of this package. Generic improvements and regressions belong here; specialized
missions and compatibility contracts belong to their downstream repositories.
