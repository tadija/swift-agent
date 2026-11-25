#!/bin/sh
set -eu
agent=${1:?usage: generic-cli-smoke.sh /absolute/path/to/swift-agent}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
export XDG_CONFIG_HOME="$fixture/config"
export XDG_DATA_HOME="$fixture/data"
mkdir "$fixture/project" "$fixture/bin"
cd "$fixture/project"
git init -q -b main
git config user.name Fixture
git config user.email fixture@example.invalid
printf 'Initial\n' > README.md
git add .
git commit -qm Initial
"$agent" --version | grep -q '^Swift Agent '
"$agent" --help | grep -q 'Usage: swift-agent '
"$agent" init
if "$agent" run > "$fixture/missing" 2>&1; then exit 1; fi
grep -q 'A mission is required' "$fixture/missing"
[ ! -e "$XDG_DATA_HOME/swift-agent" ]
cat > "$fixture/bin/documenter" <<'AGENT'
#!/bin/sh
case "$1" in *DOCUMENTATION_MISSION*) ;; *) exit 2;; esac
case "$1" in *'Do not commit, push'*) ;; *) exit 2;; esac
printf 'Documented usage example\n' > README.md
printf 'Document the usage example\n'
AGENT
chmod +x "$fixture/bin/documenter"
export PATH="$fixture/bin:$PATH"
printf '%s\n' 'DOCUMENTATION_MISSION: improve one usage example.' > "$fixture/mission.md"
printf '%s\n' '{"harness":"custom","customCommand":["documenter","{prompt}"],"verification":["test -s README.md"]}' > swift-agent.json
mkdir nested
(cd nested && "$agent" run --prompt ../../mission.md --count 2 --duration 1m) > "$fixture/run"
grep -q 'committed on swift-agent/project' "$fixture/run"
grep -q 'no_candidate on swift-agent/project' "$fixture/run"
[ "$(git rev-list --all --count)" = 2 ]
[ "$(cat README.md)" = Initial ]
[ "$(git show -s --format=%s swift-agent/project)" = 'swift-agent: Document the usage example' ]
"$agent" history > "$fixture/history"
grep -q committed "$fixture/history"
[ -d "$XDG_DATA_HOME/swift-agent/repositories" ]
# Persistent mission uses the repository root even from a nested directory.
printf '%s\n' '{"prompt":"../mission.md","harness":"custom","customCommand":["documenter","{prompt}"],"verification":["true"]}' > swift-agent.json
(cd nested && "$agent" config --prompt) > "$fixture/preview"
grep -q DOCUMENTATION_MISSION "$fixture/preview"
"$agent" run > "$fixture/configured-run"
grep -q no_candidate "$fixture/configured-run"
"$agent" schedule add --at 00:00 --duration 1m > "$fixture/schedule"
"$agent" schedule list | grep -q 'daily 00:00'
# Help must expose source update support without starting a network operation.
"$agent" update --help | grep -q 'update .*configured source'
printf 'Generic CLI smoke test passed\n'
