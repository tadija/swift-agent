#!/bin/sh
set -eu
# CLI commands; fake executables validate actual argv and working directories.
# No installed coding harness, model, credentials, or network is used.
agent=${1:?usage: cli-commands-smoke.sh /absolute/path/to/swift-agent}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/bin" "$fixture/project"
cat > "$fixture/bin/codex" <<'CODEX'
#!/bin/sh
if [ "$1" = --ask-for-approval ]; then
  [ "$2" = never ] || exit 2
  shift 2
fi
if [ "$2" = --help ]; then
  echo '--sandbox --cd --output-last-message --dangerously-bypass-approvals-and-sandbox'
  exit 0
fi
[ "$1" = exec ] || exit 2
shift
if [ "${SWIFT_AGENT_TEST_YOLO:-0}" = 1 ]; then
  [ "$1" = --dangerously-bypass-approvals-and-sandbox ] || exit 2
  shift
else
  [ "$1 $2" = '--sandbox workspace-write' ] || exit 2
  shift 2
fi
[ "$1" = --cd ] && [ "$2" -ef . ] || exit 2
shift 2
[ "$#" = 3 ] && [ "$1" = --output-last-message ] || exit 2
if [ -n "${SWIFT_AGENT_TEST_PROMPT:-}" ]; then printf '%s\n' "$3" > "$SWIFT_AGENT_TEST_PROMPT"; fi
printf 'after\n' > value.txt
printf 'Correct the value fixture\n' > "$2"
CODEX
chmod +x "$fixture/bin/codex"
export PATH="$fixture/bin:$PATH"
export XDG_DATA_HOME="$fixture/data"
export XDG_CONFIG_HOME="$fixture/config-home"
cd "$fixture"
"$agent" --version > "$fixture/version"
grep -Eq '^Swift Agent [0-9]+\.[0-9]+\.[0-9]+[^ ]*( \([^()]+\))?$' "$fixture/version"
if "$agent" --version extra > "$fixture/invalid-version" 2>&1; then exit 1; fi
cd "$fixture/project"
"$agent" init > "$fixture/init"
cp swift-agent.json "$fixture/defaults.json"
if "$agent" init > "$fixture/existing-init" 2>&1; then exit 1; fi
cmp swift-agent.json "$fixture/defaults.json"
if "$agent" init extra > "$fixture/invalid-init" 2>&1; then exit 1; fi
for command in init update run config status history stop doctor harnesses schedule; do
  "$agent" "$command" --help > "$fixture/command-help"
  grep -q 'config           Print' "$fixture/command-help"
done
if "$agent" update extra > "$fixture/invalid-update" 2>&1; then exit 1; fi
"$agent" schedule add --help > "$fixture/schedule-help"
"$agent" config --help > "$fixture/config-help"
grep -q 'Schedule subcommands:' "$fixture/schedule-help"
if "$agent" config show > "$fixture/obsolete-config" 2>&1; then exit 1; fi
git init -q -b main
git config user.name 'Fixture User'
git config user.email 'fixture@example.invalid'
printf 'before\n' > value.txt
printf '{"verification":["test -s value.txt"],"instructions":"CONFIG_INSTRUCTIONS_MUST_BE_OVERRIDDEN"}\n' > swift-agent.json
git add .
git commit -qm Initial
# The generic executable requires an explicit mission. Global paths still resolve at repo root.
printf 'FIXTURE_MISSION: improve one fixture.\n' > "$fixture/default-mission.md"
mkdir -p "$XDG_CONFIG_HOME/swift-agent"
printf '%s\n' '{"prompt":"../default-mission.md"}' > "$XDG_CONFIG_HOME/swift-agent/config.json"
"$agent" config > "$fixture/config-instructions"
grep -q 'CONFIG_INSTRUCTIONS_MUST_BE_OVERRIDDEN' "$fixture/config-instructions"
"$agent" config --prompt > "$fixture/prompt-preview"
grep -q FIXTURE_MISSION "$fixture/prompt-preview"
grep -q 'CONFIG_INSTRUCTIONS_MUST_BE_OVERRIDDEN' "$fixture/prompt-preview"
# Mission, execution contract, and runtime context each occur once.
[ "$(grep -c '^# Execution contract' "$fixture/prompt-preview")" = 1 ]
[ "$(grep -c FIXTURE_MISSION "$fixture/prompt-preview")" = 1 ]
[ "$(grep -c '^# Runtime context' "$fixture/prompt-preview")" = 1 ]
cp swift-agent.json "$fixture/project-config.json"
cp "$fixture/defaults.json" swift-agent.json
"$agent" config > "$fixture/initial-config"
cmp "$fixture/initial-config" "$fixture/defaults.json"
cp "$fixture/project-config.json" swift-agent.json
printf 'uncommitted user work\n' > value.txt
"$agent" --help > "$fixture/help"
"$agent" status > "$fixture/before"
git branch swift-agent/project
if "$agent" run > "$fixture/unowned" 2>&1; then exit 1; fi
grep -q 'use --force' "$fixture/unowned"
export SWIFT_AGENT_TEST_PROMPT="$fixture/prompt"
instructions='Focus on error handling; preserve "$HOME" and `literal` text.'
if "$agent" run --instructions > "$fixture/missing-instructions" 2>&1; then exit 1; fi
"$agent" run --force --identity "CLI Fixture <cli@example.invalid>" --instructions "$instructions" > "$fixture/run" 2> "$fixture/progress"
grep -Fq -- "$instructions" "$SWIFT_AGENT_TEST_PROMPT"
if grep -q 'CONFIG_INSTRUCTIONS_MUST_BE_OVERRIDDEN' "$SWIFT_AGENT_TEST_PROMPT"; then exit 1; fi
unset SWIFT_AGENT_TEST_PROMPT
"$agent" status > "$fixture/status"
grep -q 'Baseline' "$fixture/progress"
grep -q 'Harness' "$fixture/progress"
grep -q 'Verification' "$fixture/progress"
grep -q 'Time: .*Harness: .*Verification:' "$fixture/run"
grep -q 'committed on swift-agent/project' "$fixture/run"
grep -q 'Outcome: committed' "$fixture/status"
[ "$(git rev-list --all --count)" = 2 ]
[ "$(cat value.txt)" = 'uncommitted user work' ]
[ "$(git show swift-agent/project:value.txt)" = after ]
[ "$(git show -s --format='%an <%ae>|%cn <%ce>' swift-agent/project)" = 'CLI Fixture <cli@example.invalid>|CLI Fixture <cli@example.invalid>' ]
[ "$(git config user.name)" = 'Fixture User' ]
[ "$(git config user.email)" = 'fixture@example.invalid' ]
[ "$(git symbolic-ref --short HEAD)" = main ]
"$agent" run --count 100 > "$fixture/empty"
grep -q 'Stopped after 2 consecutive attempts without a candidate' "$fixture/empty"
[ "$(grep -c 'no_candidate on' "$fixture/empty")" = 2 ]
[ "$(git rev-list --all --count)" = 2 ]
# CLI paths resolve from the invocation directory and override repository missions.
cp swift-agent.json "$fixture/prompt-config-backup"
printf '%s\n' '{"prompt":"missing-config-mission.md","verification":["test -s value.txt"]}' > swift-agent.json
printf 'CLI_MISSION_MARKER\n' > "$fixture/mission.md"
mkdir "$fixture/project/nested"
export SWIFT_AGENT_TEST_PROMPT="$fixture/override-prompt"
(cd nested && "$agent" run --prompt ../../mission.md) > "$fixture/override-run"
grep -q CLI_MISSION_MARKER "$SWIFT_AGENT_TEST_PROMPT"
grep -q 'Do not commit, push' "$SWIFT_AGENT_TEST_PROMPT"
if grep -q FIXTURE_MISSION "$SWIFT_AGENT_TEST_PROMPT"; then exit 1; fi
for path in "$fixture/missing.md" "$fixture/empty.md"; do
  : > "$fixture/empty.md"
  if "$agent" run --prompt "$path" > "$fixture/bad-prompt" 2>&1; then exit 1; fi
  grep -q 'Cannot load prompt' "$fixture/bad-prompt"
done
if "$agent" run --prompt > "$fixture/missing-prompt-option" 2>&1; then exit 1; fi
unset SWIFT_AGENT_TEST_PROMPT
# Configuration precedence and repository-relative resolution, including global paths.
mkdir -p "$XDG_CONFIG_HOME/swift-agent"
printf '%s\n' '{"prompt":"../mission.md"}' > "$XDG_CONFIG_HOME/swift-agent/config.json"
printf '%s\n' '{}' > swift-agent.json
"$agent" config --prompt > "$fixture/global-prompt"
grep -q CLI_MISSION_MARKER "$fixture/global-prompt"
printf 'REPO_MISSION_MARKER\n' > repo-mission.md
printf '%s\n' '{"prompt":"repo-mission.md"}' > swift-agent.json
"$agent" config --prompt > "$fixture/repo-prompt"
grep -q REPO_MISSION_MARKER "$fixture/repo-prompt"
if grep -q CLI_MISSION_MARKER "$fixture/repo-prompt"; then exit 1; fi
printf '%s\n' '{"prompt":null}' > swift-agent.json
if "$agent" config --prompt > "$fixture/default-prompt" 2>&1; then exit 1; fi
grep -q 'A mission is required' "$fixture/default-prompt"
rm repo-mission.md
printf '%s\n' '{"prompt":"../default-mission.md"}' > "$XDG_CONFIG_HOME/swift-agent/config.json"
cp "$fixture/prompt-config-backup" swift-agent.json
for harness in claude pi opencode gemini custom; do
  cat > "$fixture/bin/$harness" <<'HARNESS'
#!/bin/sh
if [ "${0##*/}" = gemini ]; then
  case "$*" in *--help*)
    if [ "${SWIFT_AGENT_TEST_GEMINI_OLD:-0}" = 1 ]; then echo '--prompt'; else echo '--prompt --approval-mode auto_edit yolo'; fi
    exit 0;;
  esac
fi
case "$*" in *--help*) echo '--print --permission-mode --no-session --dangerously-skip-permissions --approve --auto'; exit 0;; esac
case "${0##*/}" in
  claude)
    if [ "${SWIFT_AGENT_TEST_YOLO:-0}" = 1 ]; then
      [ "$1 $2" = '--print --dangerously-skip-permissions' ] && shift 2 || exit 2
    else
      [ "$1 $2 $3" = '--print --permission-mode acceptEdits' ] && shift 3 || exit 2
    fi;;
  pi)
    [ "$1 $2" = '--print --no-session' ] && shift 2 || exit 2
    if [ "${SWIFT_AGENT_TEST_YOLO:-0}" = 1 ]; then [ "$1" = --approve ] && shift || exit 2; fi;;
  opencode)
    [ "$1" = run ] && shift || exit 2
    if [ "${SWIFT_AGENT_TEST_YOLO:-0}" = 1 ]; then [ "$1" = --auto ] && shift || exit 2; fi;;
  gemini)
    [ "$1" = --approval-mode ] || exit 2
    if [ "${SWIFT_AGENT_TEST_YOLO:-0}" = 1 ]; then [ "$2" = yolo ] || exit 2
    else [ "$2" = auto_edit ] || exit 2; fi
    [ "$3" = --prompt ] && shift 3 || exit 2
    [ -f value.txt ] || exit 2;;
  custom) [ "$(cd "$1" && pwd -P)" = "$(pwd -P)" ] && shift || exit 2;;
esac
[ "$#" = 1 ] || exit 2
case "$1" in *FIXTURE_MISSION*) exit 0;; *) exit 2;; esac
HARNESS
  chmod +x "$fixture/bin/$harness"
  printf '%s\n' '{"harness":"codex","customCommand":["custom","{cwd}","{prompt}"],"verification":["test -s value.txt"]}' > swift-agent.json
  "$agent" run --harness "$harness" > "$fixture/$harness.out"
  grep -q 'no_candidate on' "$fixture/$harness.out"
  if [ "$harness" != custom ]; then
    SWIFT_AGENT_TEST_YOLO=1 "$agent" run --harness "$harness" --yolo > "$fixture/$harness-yolo.out"
    grep -q 'YOLO mode enabled' "$fixture/$harness-yolo.out"
    grep -q 'no_candidate on' "$fixture/$harness-yolo.out"
  else
    if "$agent" run --harness custom --yolo > "$fixture/custom-yolo" 2>&1; then exit 1; fi
    grep -q 'only supports built-in harnesses' "$fixture/custom-yolo"
  fi
done
if SWIFT_AGENT_TEST_GEMINI_OLD=1 "$agent" run --harness gemini --yolo > "$fixture/old-gemini" 2>&1; then exit 1; fi
grep -q 'Install a compatible gemini CLI' "$fixture/old-gemini"
"$agent" harnesses > "$fixture/harnesses"
grep -q 'gemini: available' "$fixture/harnesses"
SWIFT_AGENT_TEST_YOLO=1 "$agent" run --harness codex --yolo > "$fixture/codex-yolo"
grep -q 'no_candidate on' "$fixture/codex-yolo"
"$agent" history > "$fixture/history"
grep -q committed "$fixture/history"
"$agent" config > "$fixture/config"
"$agent" schedule add --at 00:00 --duration 4h > "$fixture/schedule"
"$agent" schedule list > "$fixture/schedules"
grep -q 'daily 00:00 for 4h' "$fixture/schedules"
schedule_id=$(awk '{print $1}' "$fixture/schedules")
"$agent" schedule remove "$schedule_id" > "$fixture/removed"
"$agent" schedule list > "$fixture/schedules"
[ ! -s "$fixture/schedules" ]
if "$agent" run --until 25:00 > "$fixture/invalid" 2>&1; then exit 1; fi
if "$agent" stop > "$fixture/stop" 2>&1; then exit 1; fi
printf '%s\n' '{"baseline":[],"verification":[]}' > swift-agent.json
"$agent" run --branch swift-agent/skipped > "$fixture/skipped" 2> "$fixture/skipped-progress"
grep -q 'Baseline skipped' "$fixture/skipped-progress"
grep -q 'Verification skipped' "$fixture/skipped-progress"
grep -q 'committed on swift-agent/skipped' "$fixture/skipped"
"$agent" doctor > "$fixture/skipped-doctor"
grep -q 'Baseline: skipped. Verification: skipped' "$fixture/skipped-doctor"
# The CLI flag overrides both phases without changing configuration.
printf '%s\n' '{"baseline":["false"],"verification":["false"]}' > swift-agent.json
cp swift-agent.json "$fixture/skip-config"
"$agent" run --skip-checks --branch swift-agent/skip-both > "$fixture/skip-both" 2> "$fixture/skip-both-progress"
grep -q 'committed on swift-agent/skip-both' "$fixture/skip-both"
grep -q 'Baseline skipped' "$fixture/skip-both-progress"
grep -q 'Verification skipped' "$fixture/skip-both-progress"
cmp swift-agent.json "$fixture/skip-config"
printf '%s\n' '{}' > swift-agent.json
"$agent" run --skip-checks --branch swift-agent/no-verification > "$fixture/no-verification" 2> "$fixture/no-verification-progress"
grep -q 'committed on swift-agent/no-verification' "$fixture/no-verification"
if "$agent" run --branch swift-agent/needs-verification > "$fixture/needs-verification" 2>&1; then exit 1; fi
grep -q 'No meaningful verification detected' "$fixture/needs-verification"
# Every value option rejects a missing value, and boolean switches take no value.
for option in --prompt --ollama-model --ollama-host --instructions --identity --branch --base --count --harness --duration --until --unknown; do
  if "$agent" run "$option" > "$fixture/incomplete" 2>&1; then exit 1; fi
  grep -q 'Unknown or incomplete option' "$fixture/incomplete"
done
for count in 0 -1 nope 1.5; do
  if "$agent" run --count "$count" > "$fixture/bad-count" 2>&1; then exit 1; fi
  grep -q 'positive integer' "$fixture/bad-count"
done
if "$agent" run --prompt ' ' > "$fixture/blank-prompt" 2>&1; then exit 1; fi
grep -q 'nonempty path' "$fixture/blank-prompt"
if "$agent" run --duration 1m --until 23:59 > "$fixture/two-windows" 2>&1; then exit 1; fi
grep -q 'only one execution window' "$fixture/two-windows"
if "$agent" run --until 23:59 --duration 1m > "$fixture/two-windows" 2>&1; then exit 1; fi
grep -q 'only one execution window' "$fixture/two-windows"
# CLI count, branch, base, identity, and harness override configured values without persisting.
printf '%s\n' '{"prompt":"../default-mission.md","maxIterations":5,"branch":"swift-agent/global","base":"missing-global-ref","commitIdentity":"Global Fixture <global@example.invalid>","harness":"pi","instructions":"GLOBAL_GUIDANCE","baseline":["false"],"verification":["false"]}' > "$XDG_CONFIG_HOME/swift-agent/config.json"
printf '%s\n' '{"maxIterations":3,"branch":"swift-agent/configured","base":"missing-configured-ref","commitIdentity":"Config Fixture <config@example.invalid>","harness":"claude","instructions":"REPO_GUIDANCE","baseline":[],"verification":[]}' > swift-agent.json
"$agent" config > "$fixture/layered-config"
grep -q '"maxIterations" : 3' "$fixture/layered-config"
grep -q '"harness" : "claude"' "$fixture/layered-config"
grep -q 'Config Fixture' "$fixture/layered-config"
if grep -Eq 'GLOBAL_GUIDANCE|missing-global-ref|Global Fixture|swift-agent/global|"false"' "$fixture/layered-config"; then exit 1; fi
export SWIFT_AGENT_TEST_PROMPT="$fixture/layered-prompt"
cp swift-agent.json "$fixture/precedence-config"
"$agent" run --count 1 --branch swift-agent/cli --base main --identity git --harness codex > "$fixture/precedence-run"
grep -q 'committed on swift-agent/cli' "$fixture/precedence-run"
[ "$(grep -c ' on swift-agent/cli' "$fixture/precedence-run")" = 1 ]
[ "$(git show -s --format='%an <%ae>|%cn <%ce>' swift-agent/cli)" = 'Fixture User <fixture@example.invalid>|Fixture User <fixture@example.invalid>' ]
[ -z "$(git branch --list swift-agent/configured)" ]
grep -q REPO_GUIDANCE "$SWIFT_AGENT_TEST_PROMPT"
if grep -q GLOBAL_GUIDANCE "$SWIFT_AGENT_TEST_PROMPT"; then exit 1; fi
unset SWIFT_AGENT_TEST_PROMPT
cmp swift-agent.json "$fixture/precedence-config"
# Ollama CLI options are validated even with a command harness; never contact a server.
if "$agent" run --ollama-model ' ' > "$fixture/model" 2>&1; then exit 1; fi
grep -q 'Invalid Ollama settings' "$fixture/model"
if "$agent" run --ollama-host file:///tmp/model > "$fixture/host" 2>&1; then exit 1; fi
grep -q 'Invalid Ollama settings' "$fixture/host"
printf 'CLI command smoke test passed\n'
