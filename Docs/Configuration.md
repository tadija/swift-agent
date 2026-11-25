# Repository configuration

Run `swift-agent init` in the root of your checkout to generate an optional `swift-agent.json` with every property set to its built-in default. It refuses to overwrite an existing file and works before Git initialization. Edit the file for your project, or keep only the settings you need. Run `swift-agent config` to inspect the effective settings.

```sh
swift-agent init
swift-agent config
swift-agent config --prompt
```

`swift-agent config` includes the configured `instructions` string. `swift-agent config --prompt`
prints the full prompt that the next iteration would send, including the mandatory execution
contract, resolved mission, configured project guidance, and recent outcomes for the configured
target branch. It does not invoke a harness. History changes after each iteration.
Overrides passed to a previous `swift-agent run --instructions` are not saved; this preview
uses the current global and repository configuration.

Automatic settings (`prompt`, `base`, `branch`, `harness`, `customCommand`, `ollamaModel`, `baseline`, and `verification`) are written as `null`. For baseline and verification, `null` has the same automatic behavior as omitting the property; `[]` explicitly skips commands. The generated file uses built-in defaults, independent of global settings, and its explicit values override global settings.

A minimal hand-written configuration also works:

```json
{
  "verification": ["python3 -m unittest discover -s tests"],
  "instructions": "Prioritize error handling in the importer."
}
```

| Setting | Default or behavior |
| --- | --- |
| `baseline` | Ordered shell commands before the harness. Defaults to the resolved `verification` commands. Set `[]` to skip baseline commands. |
| `verification` | Ordered shell commands for the proposed change in a fresh checkout. Include any setup they need. Defaults to `swift test` for Swift packages; otherwise commands must be configured. Set `[]` to explicitly skip project verification. |
| `protectedPaths` | Additional case-sensitive POSIX glob patterns against repository-relative paths. `*` can match slashes, e.g. `vendor/*`. Built-in protections always apply. |
| `prompt` | `null` requires a mission via `--prompt PATH`; the generic executable has no embedded mission. A UTF-8 Markdown path replaces the mission. Override for one run with `--prompt PATH`. Configured relative paths use the original repository root (including global config); CLI relative paths use the invocation directory. Explicit missing, unreadable, invalid UTF-8, or whitespace-only files fail. |
| `instructions` | Additional project preferences for the agent. Override for one run with `--instructions "..."`. |
| `harness` | Automatic discovery, or choose `codex`, `claude`, `pi`, `opencode`, `gemini`, `ollama`, or `custom`. |
| `ollamaModel` | `null`; required when selecting Ollama. Name of an installed model with tool support. Override with `--ollama-model`. |
| `ollamaHost` | `http://127.0.0.1:11434`; server base URL. Override with `--ollama-host`. |
| `ollamaMaxTurns` | 40 model responses per iteration (1–200). Exhaustion fails the iteration without committing. |
| `ollamaContextLength` | 32768 context tokens per request (4096–1048576). Set according to model support and server memory. |
| `customCommand` | For a custom harness, give the executable and arguments as an array, e.g. `["my-agent", "{prompt}"]`. Use `{cwd}` for the worktree path. Arguments are passed directly. |
| `commitIdentity` | Author and committer for SwiftAgent commits. Default: `Swift Agent <swift-agent@localhost>`. Set `git` to use the configured Git identity, or supply `Name <email>`. Override with `--identity`. |
| `base`, `branch` | Starting revision and local target branch. Defaults are HEAD and `swift-agent/<project>`. |
| `maxIterations` | 1 attempt per invocation. Override with `--count`. |
| `failureLimit`, `saturationLimit` | 3 consecutive failures or 2 consecutive empty attempts. |
| `timeoutSeconds`, `maxChangedFiles` | 1800 seconds per iteration and 12 changed files. |

Global defaults may be set in `$XDG_CONFIG_HOME/swift-agent/config.json` (normally
`~/.config/swift-agent/config.json`). Repository config overrides global settings and CLI
flags override repository settings. `push: true` explicitly enables non-forced
pushes to `origin` after accepted commits. A failed push retains the local commit
and stops the run.

[Example configuration](Examples/swift-agent.json)

## Permissive harness mode

```sh
swift-agent run --harness claude --yolo
```

`--yolo` is a per-run CLI flag. It selects the built-in agent's supported permissive arguments:

| Harness | Arguments used in YOLO mode | Effect |
| --- | --- | --- |
| Codex | `--dangerously-bypass-approvals-and-sandbox` instead of `--ask-for-approval never` and `--sandbox workspace-write` | Disables Codex approval prompts and sandboxing. |
| Claude Code | `--dangerously-skip-permissions` instead of `--permission-mode acceptEdits` | Bypasses Claude permission checks. |
| Pi | Adds `--approve` | Trusts project-local resources for this invocation. Pi already runs tools without per-call approvals. |
| OpenCode | Adds `--auto` | Auto-approves permissions that are not explicitly denied. Explicit denials still apply. |
| Gemini | `--approval-mode yolo` instead of `--approval-mode auto_edit` | Auto-approves all tool calls instead of just edit tools. |
| Ollama | No additional effect | Shell commands are available by default. File tools retain path restrictions. |

External CLI mappings are checked against each installed CLI's help output before execution. Older versions missing these flags are rejected. Custom harnesses must configure their own arguments in `customCommand`; combining them with `--yolo` is rejected.

This affects the agent process's execution permissions, not SwiftAgent's Git guards, verification commands, or publishing rules. Codex's sandbox is disabled in this mode; a Git worktree does not restrict filesystem or network access. Normal arguments remain the default when the flag is absent. See [Pi's security model](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/security.md) for the distinction between project trust and tool permissions. Other mappings were verified with the installed `codex exec --help`, `claude --help`, and `opencode run --help`.

Gemini runs headlessly with `--prompt` from the SwiftAgent worktree. Normal mode uses
`auto_edit`; tools that require additional approval may be denied in headless mode.
Use `swift-agent run --harness gemini --yolo` for Gemini's permissive mode. These arguments
were checked against the installed `gemini --help` and the official
[Gemini reference](https://geminicli.com/docs/cli/cli-reference/).

## Ollama

Ollama runs through SwiftAgent's own tool-calling agent; Codex and other agent CLIs are
not required. Use the base URL of your server, the same address whose root page
says “Ollama is running,” and an installed model that supports tools:

```sh
swift-agent run --harness ollama --ollama-host http://192.168.1.50:11434 --ollama-model my-coding-model
```

Replace `my-coding-model` with a model installed on your server. To keep the settings:

```json
{
  "harness": "ollama",
  "ollamaHost": "http://192.168.1.50:11434",
  "ollamaModel": "my-coding-model",
  "ollamaMaxTurns": 40,
  "ollamaContextLength": 32768,
  "verification": ["swift test"]
}
```

Use your project's verification commands. `swift-agent doctor` checks connectivity and
model tool support via `/api/show`; SwiftAgent never pulls a model or starts an Ollama
server. An Ollama CLI installation is not needed on the SwiftAgent machine. The server
must be listening on an address reachable from that machine. See Ollama's
[network configuration](https://docs.ollama.com/faq#how-can-i-expose-ollama-on-my-network)
for server-side setup. Repository content and project guidance are sent to the
configured server, so choose an endpoint you trust.

The agent can list unignored and tracked files, read text, search literal strings,
write files, and replace unique text matches. File tools stay inside the worktree,
reject symlinks and secret paths, and enforce SwiftAgent's protected paths when writing.
File reads/writes are limited to 1 MiB, tool responses to 32 KiB, and each model
response to 16 tool calls. Text files can be read in pages using line ranges.
Baseline and verification commands still run independently as configured.

Shell commands are available by default through `run_command`, so the agent can
inspect Git diffs and run builds or tests without `--yolo`. Those commands run
with the SwiftAgent process's permissions and can access paths outside the worktree;
SwiftAgent's normal Git and final diff checks still apply. `--yolo` has no additional
effect on Ollama. Runs respect cancellation,
the iteration deadline, and `ollamaMaxTurns`; failed or unfinished runs do not
publish partial edits. Each iteration starts a fresh conversation.

Ollama comes last in discovery order and is available for discovery only when
`ollamaModel` is configured and the server advertises tool support. Select
`--harness ollama` explicitly to ensure a run uses it. API requests follow the
[Ollama tool-calling protocol](https://docs.ollama.com/capabilities/tool-calling).
Use locally installed models and your server's local-only settings if you need
inference to stay on your own infrastructure; SwiftAgent does not control Ollama's cloud model routing.

## Instructions from the CLI

```sh
swift-agent run --instructions "Focus on error handling; preserve public APIs."
```

The quoted text replaces configured `instructions` for this invocation and applies to every iteration. Use `--instructions ""` to clear configured guidance for a run. No `swift-agent.json` file is required; SwiftAgent's built-in constraints remain in effect.

## Baseline and verification

Skip both phases for one invocation without changing configuration:

```sh
swift-agent run --skip-checks
```

`--skip-checks` takes no value and skips baseline and verification commands for
every iteration in the run, including configured commands and automatic Swift
checks. It also permits running projects without detected verification.
To skip only one phase, configure its command array as `[]`.

Commands run in order from the worktree root, in each phase's separate checkout. Include dependency installation or other setup in each phase that needs it; baseline build artifacts are not shared with verification. Command failures are recorded; publishing requires all final verification commands to succeed. Baseline failures are retained for comparison and diagnostics.

For a Swift package, the defaults run `swift test` in both phases. To use a quick baseline and a broader final check:

```json
{
  "baseline": ["swift build"],
  "verification": ["swift test", "swift build -c release"]
}
```

For a Rust project, check compilation first, then run tests and Clippy (requires the Clippy component):

```json
{
  "baseline": ["cargo check --all-targets"],
  "verification": ["cargo test --all-targets", "cargo clippy --all-targets -- -D warnings"]
}
```

For a TypeScript project using npm and a committed `package-lock.json`, install dependencies in both checkouts. This example assumes `typecheck`, `test`, and `build` scripts in `package.json`, with `test` configured to exit after one run:

```json
{
  "baseline": ["npm ci", "npm run typecheck"],
  "verification": ["npm ci", "npm run typecheck", "npm test", "npm run build"]
}
```

Adapt commands to your project's scripts and toolchain. To run identical commands in both phases, configure only `verification`.

Skip baseline commands while keeping final verification:

```json
{
  "baseline": [],
  "verification": ["swift test"]
}
```

Use different commands for each phase by providing both arrays. Omitted `baseline` uses the resolved verification commands. Omitted `verification` uses automatic Swift detection; other projects still require explicit configuration.

To skip both sets of project commands, set `"baseline": []` and `"verification": []`. An empty `verification` array also skips baseline commands when `baseline` is omitted. Explicit empty arrays override automatic detection. Empty strings inside either array are invalid.

Skipping commands is an explicit opt-in to commits without those project checks. Git isolation, protected-path checks, diff validation, and clean-tree integrity checks still run. The harness may run its own tests independently.

## Commit identity

```sh
swift-agent run --identity "Custom Scout <scout@example.com>"
swift-agent run --identity git
```

Specialized products can declare their built-in default with `commitIdentity` in
build-time `agent.json`, mapped through `AgentDefinition(commitIdentity:)`.
Runtime repository/global configuration and `--identity` override that default.

Both author and committer use the selected identity. It applies only when SwiftAgent creates its commit; repository and global Git configuration are unchanged. `git` uses Git's configured author/committer identities and requires a usable Git identity. Inherited `GIT_*` environment variables are filtered by SwiftAgent.

To keep your Git identity for every run, set `"commitIdentity": "git"` in your repository or global SwiftAgent config. Scheduled runs use these same config files.

## Mission Markdown

The generic executable requires CLI `--prompt PATH` or a configured `prompt`.
Specialized agents may supply an embedded mission in their `AgentDefinition`.
Precedence is CLI, repository config, global config, then the definition's mission.
A repository `null` clears a global override. Missing, unreadable, invalid UTF-8,
or blank explicit missions fail before execution. CLI paths resolve from the
invocation directory; configured paths resolve from the original repository root.
The resolved mission stays fixed for the session.

The engine composes its mandatory execution contract, the mission, additional
project instructions, and recent branch history. Overrides cannot remove Git,
protected-path, verification, or commit gates. `swift-agent config --prompt`
previews that composition without invoking a harness.

For persistent documentation work:

```json
{
  "prompt": "missions/documentation.md",
  "verification": ["swift test"],
  "maxIterations": 3
}
```

Configure a persistent mission before scheduling; wrappers reload configuration.
Specialized executables derive their config filename, state, branches, identities,
and schedules from their definition. See [creating an agent](API.md).
