#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RALPH="$REPOSITORY_ROOT/ralph"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"

    grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

write_tasks() {
    local workspace="$1"

    cat > "$workspace/tasks.json" <<'EOF'
{
  "branchName": "ralph/test-loop",
  "userStories": [
    {
      "id": "US-001",
      "title": "Exercise the adapter",
      "description": "Let the fake backend complete one story.",
      "acceptanceCriteria": ["The fake backend ran"],
      "priority": 1,
      "passes": false
    }
  ]
}
EOF
}

make_workspace() {
    local name="$1"
    local workspace="$TEST_ROOT/$name"

    mkdir -p "$workspace"
    git -C "$workspace" init -q
    RALPH_WORKSPACE="$workspace" "$RALPH" init >/dev/null
    write_tasks "$workspace"
    printf '%s\n' "$workspace"
}

MOCK_BIN="$TEST_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/fake-agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

tool="$(basename "$0")"
printf '%s|%s|%s\n' "$tool" "$$" "$*" >> "$RALPH_WORKSPACE/invocations.log"

if [[ "$tool" == "opencode" ]]; then
    prompt="$*"
else
    prompt="$(cat)"
fi
[[ "$prompt" == *"# Ralph Agent Instructions"* ]]

count="$(wc -l < "$RALPH_WORKSPACE/invocations.log")"
if [[ "${FAKE_FAIL_FIRST:-0}" == "1" && "$count" == "1" ]]; then
    exit 7
fi

jq '.userStories[0].passes = true' "$RALPH_WORKSPACE/tasks.json" > "$RALPH_WORKSPACE/tasks.json.tmp"
mv "$RALPH_WORKSPACE/tasks.json.tmp" "$RALPH_WORKSPACE/tasks.json"
printf '\n## fake progress\n' >> "$RALPH_WORKSPACE/progress.md"
echo '<promise>COMPLETE</promise>'
EOF
chmod 0755 "$MOCK_BIN/fake-agent"
ln -s fake-agent "$MOCK_BIN/codex"
ln -s fake-agent "$MOCK_BIN/claude"
ln -s fake-agent "$MOCK_BIN/opencode"

init_workspace="$TEST_ROOT/init"
mkdir -p "$init_workspace"
printf 'existing\n' > "$init_workspace/.gitignore"
RALPH_WORKSPACE="$init_workspace" "$RALPH" init >/dev/null
[[ -f "$init_workspace/AGENTS-RALPH.md" ]] || fail 'init did not create instructions'
[[ -f "$init_workspace/tasks.json" ]] || fail 'init did not create tasks'
[[ -f "$init_workspace/progress.md" ]] || fail 'init did not create progress'
assert_contains "$init_workspace/.gitignore" '/tasks.json'
assert_contains "$init_workspace/.gitignore" '/progress.md'
instructions_checksum="$(sha256sum "$init_workspace/AGENTS-RALPH.md")"
RALPH_WORKSPACE="$init_workspace" "$RALPH" init >/dev/null
[[ "$(sha256sum "$init_workspace/AGENTS-RALPH.md")" == "$instructions_checksum" ]] || fail 'init overwrote instructions'
[[ "$(grep -Fxc '/tasks.json' "$init_workspace/.gitignore")" == "1" ]] || fail 'init duplicated tasks ignore rule'
[[ "$(grep -Fxc '/progress.md' "$init_workspace/.gitignore")" == "1" ]] || fail 'init duplicated progress ignore rule'

for tool in codex claude opencode; do
    workspace="$(make_workspace "$tool")"
    PATH="$MOCK_BIN:$PATH" RALPH_WORKSPACE="$workspace" "$RALPH" --tool "$tool" 1 >/dev/null
    assert_contains "$workspace/invocations.log" "$tool|"
    case "$tool" in
        codex) assert_contains "$workspace/invocations.log" 'exec --ephemeral --sandbox danger-full-access -' ;;
        claude) assert_contains "$workspace/invocations.log" '--dangerously-skip-permissions --print' ;;
        opencode) assert_contains "$workspace/invocations.log" '--dangerously-skip-permissions run' ;;
    esac
    jq -e 'all(.userStories[]; .passes)' "$workspace/tasks.json" >/dev/null || fail "$tool did not complete tasks"
done

recovery_workspace="$(make_workspace recovery)"
PATH="$MOCK_BIN:$PATH" RALPH_WORKSPACE="$recovery_workspace" FAKE_FAIL_FIRST=1 \
    "$RALPH" --tool codex 2 >/dev/null 2>&1
[[ "$(wc -l < "$recovery_workspace/invocations.log")" == "2" ]] || fail 'failed iteration was not retried'
[[ "$(cut -d '|' -f 2 "$recovery_workspace/invocations.log" | sort -u | wc -l)" == "2" ]] || fail 'iterations did not use fresh processes'

invalid_workspace="$(make_workspace invalid)"
printf '{}\n' > "$invalid_workspace/tasks.json"
if PATH="$MOCK_BIN:$PATH" RALPH_WORKSPACE="$invalid_workspace" "$RALPH" --tool codex 1 >/dev/null 2>&1; then
    fail 'invalid tasks.json was accepted'
fi

echo 'Ralph tests passed.'
