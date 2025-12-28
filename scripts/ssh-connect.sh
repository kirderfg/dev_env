#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

# Load config
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
else
    echo "Error: Config file not found at ${ENV_FILE}"
    echo "Run ./scripts/deploy.sh first."
    exit 1
fi

# Expand ~ in SSH_KEY_PATH
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

# Check if SSH key exists
if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo "Error: SSH key not found at ${SSH_KEY_PATH}"
    echo "Run ./scripts/deploy.sh first."
    exit 1
fi

# Set Windows Terminal tab title
set_tab_title() {
    printf '\033]0;%s\007' "$1"
}

# Restore title on exit (trap handles Ctrl+C and normal exit)
restore_title() {
    set_tab_title "${PWD##*/}"
}
trap restore_title EXIT

# Rename tab to "Dev VM"
set_tab_title "Dev VM"

# Discover ports from devcontainers and docker-compose files in git repos on remote
discover_ports() {
    ssh -i "${SSH_KEY_PATH}" \
        -o StrictHostKeyChecking=accept-new \
        -o LogLevel=ERROR \
        -o ConnectTimeout=5 \
        "${SSH_USER}@${VM_IP}" 'bash -s' << 'DISCOVER_EOF'
#!/bin/bash
ports=""

# Find all git repositories in home directory
for git_dir in $(find ~ -maxdepth 3 -type d -name ".git" 2>/dev/null); do
    repo_dir=$(dirname "$git_dir")

    # Check for devcontainer.json
    devcontainer="${repo_dir}/.devcontainer/devcontainer.json"
    if [ -f "$devcontainer" ]; then
        if grep -q "forwardPorts" "$devcontainer" 2>/dev/null; then
            extracted=$(grep -oP '"forwardPorts"\s*:\s*\[\K[^\]]+' "$devcontainer" 2>/dev/null | tr -d ' "' | tr ',' '\n')
            ports="$ports $extracted"
        fi
    fi

    # Check for docker-compose files in repo root
    for compose in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
        compose_file="${repo_dir}/${compose}"
        if [ -f "$compose_file" ]; then
            extracted=$(grep -oP '^\s*-\s*["\x27]?\K\d+(?=:|\d*["\x27]?\s*$)' "$compose_file" 2>/dev/null)
            ports="$ports $extracted"
        fi
    done
done

# Deduplicate and sort
echo "$ports" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | uniq | tr '\n' ' '
DISCOVER_EOF
}

echo "Discovering ports from devcontainers..."
DISCOVERED_PORTS=$(discover_ports 2>/dev/null || echo "")

# Build port forward arguments
PORT_ARGS=""
if [ -n "$DISCOVERED_PORTS" ]; then
    echo "Found ports: $DISCOVERED_PORTS"
    for port in $DISCOVERED_PORTS; do
        PORT_ARGS="$PORT_ARGS -L ${port}:localhost:${port}"
    done
else
    echo "No ports discovered, using defaults"
    PORT_ARGS="-L 3000:localhost:3000 -L 5000:localhost:5000 -L 5173:localhost:5173 -L 8283:localhost:8283 -L 5432:localhost:5432"
fi

echo "Connecting to ${VM_IP}..."
# shellcheck disable=SC2086
ssh -i "${SSH_KEY_PATH}" \
    -o StrictHostKeyChecking=accept-new \
    -o LogLevel=ERROR \
    $PORT_ARGS \
    "${SSH_USER}@${VM_IP}"
