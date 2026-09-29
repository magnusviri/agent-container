#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/workspace"
cat > "$TEST_ROOT/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_LOG"
if [[ "${1:-}" == "ps" ]]; then
    if [[ -f "$DOCKER_RUNTIME_STATE" || "$DOCKER_STATE" == "running" ]]; then
        echo 'fake-container'
    elif [[ "$DOCKER_STATE" == "stopped" && " $* " == *" -a "* ]]; then
        echo 'fake-container'
    fi
elif [[ "${1:-}" == "start" ]]; then
    : > "$DOCKER_RUNTIME_STATE"
elif [[ "${1:-}" == "inspect" ]]; then
    if [[ "${DOCKER_CONTROL_MOUNT:-tmpfs}" == "tmpfs" ]]; then
        echo 'tmpfs'
    fi
elif [[ "${1:-}" == "run" && " $* " == *" --detach "* ]]; then
    : > "$DOCKER_RUNTIME_STATE"
    echo 'fake-container'
elif [[ "${1:-}" == "stop" ]]; then
    rm -f "$DOCKER_RUNTIME_STATE"
fi
EOF
chmod 0755 "$TEST_ROOT/bin/docker"

DOCKER_LOG="$TEST_ROOT/bash-build-docker.log" \
DOCKER_STATE=none \
DOCKER_RUNTIME_STATE="$TEST_ROOT/bash-build.state" \
PATH="$TEST_ROOT/bin:$PATH" \
AI_AGENT_HOME="$REPOSITORY_ROOT" \
    "$REPOSITORY_ROOT/agent" build \
    < /dev/null > /dev/null

grep -Fq "build --build-arg PROJECT_VERSION=0.1.0 --tag agent-container:0.1.0 --tag agent-container:latest $REPOSITORY_ROOT" \
    "$TEST_ROOT/bash-build-docker.log" || fail 'Bash launcher did not apply release and latest image tags'

DOCKER_LOG="$TEST_ROOT/powershell-build-docker.log" \
DOCKER_STATE=none \
DOCKER_RUNTIME_STATE="$TEST_ROOT/powershell-build.state" \
PATH="$TEST_ROOT/bin:$PATH" \
AI_AGENT_HOME="$REPOSITORY_ROOT" \
    pwsh -NoLogo -NoProfile -File "$REPOSITORY_ROOT/agent.ps1" build \
    < /dev/null > /dev/null

grep -Fq "build --build-arg PROJECT_VERSION=0.1.0 --tag agent-container:0.1.0 --tag agent-container:latest $REPOSITORY_ROOT" \
    "$TEST_ROOT/powershell-build-docker.log" || fail 'PowerShell launcher did not apply release and latest image tags'

DOCKER_LOG="$TEST_ROOT/bash-docker.log" \
DOCKER_STATE=running \
DOCKER_RUNTIME_STATE="$TEST_ROOT/bash-running.state" \
PATH="$TEST_ROOT/bin:$PATH" \
AI_AGENT_HOME="$REPOSITORY_ROOT" \
    "$REPOSITORY_ROOT/agent" ralph --tool codex 3 \
    < /dev/null > /dev/null

grep -Fq 'exec --interactive --user agent --env HOME=/home/agent --workdir /workspace --env PATH=/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin fake-container ralph --tool codex 3' \
    "$TEST_ROOT/bash-docker.log" || fail 'Bash launcher did not route Ralph through docker exec'

if DOCKER_LOG="$TEST_ROOT/bash-legacy-docker.log" \
    DOCKER_STATE=running \
    DOCKER_CONTROL_MOUNT=missing \
    DOCKER_RUNTIME_STATE="$TEST_ROOT/bash-legacy-running.state" \
    PATH="$TEST_ROOT/bin:$PATH" \
    AI_AGENT_HOME="$REPOSITORY_ROOT" \
    "$REPOSITORY_ROOT/agent" < /dev/null > /dev/null 2> "$TEST_ROOT/bash-legacy.err"; then
    fail 'Bash launcher accepted a container without Codex socket isolation'
fi
grep -Fq 'predates Codex control-socket isolation' "$TEST_ROOT/bash-legacy.err" \
    || fail 'Bash launcher did not explain the missing Codex socket isolation'

DOCKER_LOG="$TEST_ROOT/bash-exec-docker.log" \
DOCKER_STATE=running \
DOCKER_RUNTIME_STATE="$TEST_ROOT/bash-exec-running.state" \
PATH="$TEST_ROOT/bin:$PATH" \
AI_AGENT_HOME="$REPOSITORY_ROOT" \
    "$REPOSITORY_ROOT/agent" exec terraform \
    < /dev/null > /dev/null

grep -Fq 'exec --interactive --user agent --env HOME=/home/agent --workdir /workspace --env PATH=/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin fake-container terraform' \
    "$TEST_ROOT/bash-exec-docker.log" || fail 'Bash launcher did not expose mise shims to agent exec commands'

DOCKER_LOG="$TEST_ROOT/powershell-docker.log" \
DOCKER_STATE=running \
DOCKER_RUNTIME_STATE="$TEST_ROOT/powershell-running.state" \
PATH="$TEST_ROOT/bin:$PATH" \
AI_AGENT_HOME="$REPOSITORY_ROOT" \
    pwsh -NoLogo -NoProfile -File "$REPOSITORY_ROOT/agent.ps1" ralph --tool opencode 4 \
    < /dev/null > /dev/null

grep -Fq 'exec --interactive --user agent --env HOME=/home/agent --workdir /workspace --env PATH=/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin fake-container ralph --tool opencode 4' \
    "$TEST_ROOT/powershell-docker.log" || fail 'PowerShell launcher did not route Ralph through docker exec'

DOCKER_LOG="$TEST_ROOT/bash-new-docker.log" \
DOCKER_STATE=none \
DOCKER_RUNTIME_STATE="$TEST_ROOT/bash-new.state" \
PATH="$TEST_ROOT/bin:$PATH" \
AI_AGENT_HOME="$REPOSITORY_ROOT" \
    "$REPOSITORY_ROOT/agent" ralph init \
    < /dev/null > /dev/null

grep -Fq 'run --detach --interactive --init' "$TEST_ROOT/bash-new-docker.log" || fail 'Bash launcher did not create a detached Ralph container'
grep -Fq 'sleep infinity' "$TEST_ROOT/bash-new-docker.log" || fail 'Bash launcher did not create a reusable container'
grep -Fq 'exec --interactive --user agent --env HOME=/home/agent --workdir /workspace --env PATH=/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin agent-' \
    "$TEST_ROOT/bash-new-docker.log" || fail 'Bash launcher did not execute Ralph in the new container'
grep -Fq 'ralph init' "$TEST_ROOT/bash-new-docker.log" || fail 'Bash launcher lost Ralph arguments'

DOCKER_LOG="$TEST_ROOT/powershell-stopped-docker.log" \
DOCKER_STATE=stopped \
DOCKER_RUNTIME_STATE="$TEST_ROOT/powershell-stopped.state" \
PATH="$TEST_ROOT/bin:$PATH" \
AI_AGENT_HOME="$REPOSITORY_ROOT" \
    pwsh -NoLogo -NoProfile -File "$REPOSITORY_ROOT/agent.ps1" ralph --tool claude 2 \
    < /dev/null > /dev/null

grep -Fq 'start fake-container' "$TEST_ROOT/powershell-stopped-docker.log" || fail 'PowerShell launcher did not start the stopped container'
grep -Fq 'exec --interactive --user agent --env HOME=/home/agent --workdir /workspace --env PATH=/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin fake-container ralph --tool claude 2' \
    "$TEST_ROOT/powershell-stopped-docker.log" || fail 'PowerShell launcher did not execute Ralph in the stopped container'

echo 'Ralph launcher tests passed.'
