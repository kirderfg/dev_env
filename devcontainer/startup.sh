#!/bin/bash
# DevPod container startup script
# Runs on every container start (not just first create)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== DevPod Container Startup ==="

# Get workspace root directory
get_workspace_root() {
    if [[ -d "/workspaces" ]]; then
        find /workspaces -maxdepth 1 -type d ! -name workspaces | head -1
    else
        dirname "$SCRIPT_DIR"
    fi
}

# Run a local hook script if it exists
run_local_hook() {
    local hook_name="$1"
    local description="$2"
    local workspace_root
    workspace_root="$(get_workspace_root)"

    if [[ -z "$workspace_root" || ! -d "$workspace_root" ]]; then
        return 0
    fi

    local hook_path="${workspace_root}/.devcontainer.local/${hook_name}"
    if [[ -f "$hook_path" ]]; then
        echo "Running local ${description} hook..."
        source "$hook_path"
    fi
}

# Ensure Tailscale is running
start_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        echo "Tailscale not installed, skipping"
        return 0
    fi

    # Check if tailscaled is already running
    if pgrep tailscaled > /dev/null; then
        echo "Tailscale daemon already running"
        return 0
    fi

    echo "Starting Tailscale daemon..."
    sudo tailscaled \
        --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock > /tmp/tailscaled.log 2>&1 &
    sleep 2

    # Check status
    if sudo tailscale status &>/dev/null; then
        echo "Tailscale connected"
    else
        echo "Tailscale not connected (may need re-auth)"
    fi
}

# Source persisted secrets
load_secrets() {
    if [[ -f ~/.config/dev_env/secrets.sh ]]; then
        source ~/.config/dev_env/secrets.sh
    fi
}

# Main startup
main() {
    # Run pre-startup hook
    run_local_hook "pre-startup.sh" "pre-startup"

    start_tailscale
    load_secrets

    # Run post-startup hook
    run_local_hook "startup.sh" "post-startup"

    echo "=== Startup Complete ==="
}

main "$@"
