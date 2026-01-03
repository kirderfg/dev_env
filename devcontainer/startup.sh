#!/bin/bash
# DevPod container startup script
# Runs on every container start (not just first create)

set -e

echo "=== DevPod Container Startup ==="

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
    start_tailscale
    load_secrets

    echo "=== Startup Complete ==="
}

main "$@"
