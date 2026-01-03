#!/bin/bash
# DevPod container one-time setup
# Secrets are injected as environment variables by dp.sh
# NO 1Password CLI installed - secrets come from env vars

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== DevPod Container Setup ==="

# Persist injected secrets for shell init (so they survive shell restarts)
persist_secrets() {
    echo "Persisting secrets..."
    mkdir -p ~/.config/dev_env
    chmod 700 ~/.config/dev_env

    cat > ~/.config/dev_env/secrets.sh << EOF
# Secrets persisted from devpod env vars
# Source this in your shell init

export GITHUB_TOKEN="${GITHUB_TOKEN:-}"
export GH_TOKEN="${GH_TOKEN:-}"
export ATUIN_USERNAME="${ATUIN_USERNAME:-}"
export ATUIN_PASSWORD="${ATUIN_PASSWORD:-}"
export ATUIN_KEY="${ATUIN_KEY:-}"
export PET_GITHUB_TOKEN="${PET_GITHUB_TOKEN:-}"
EOF
    chmod 600 ~/.config/dev_env/secrets.sh
    echo "Secrets persisted to ~/.config/dev_env/secrets.sh"
}

# Setup Tailscale with tagged key
setup_tailscale() {
    echo "Setting up Tailscale..."

    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        echo "TAILSCALE_AUTH_KEY not set, skipping Tailscale setup"
        return 0
    fi

    local hostname="devpod-${DEVPOD_WORKSPACE_ID:-unknown}"

    # Install Tailscale if not present
    if ! command -v tailscale &> /dev/null; then
        echo "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    # Start daemon
    echo "Starting Tailscale daemon..."
    sudo tailscaled \
        --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock > /tmp/tailscaled.log 2>&1 &
    sleep 2

    # Cleanup old device if API key available
    if [[ -n "$TAILSCALE_API_KEY" ]]; then
        echo "Checking for old Tailscale device..."
        local old_id
        old_id=$(curl -s -H "Authorization: Bearer $TAILSCALE_API_KEY" \
            "https://api.tailscale.com/api/v2/tailnet/-/devices" | \
            jq -r ".devices[] | select(.name | startswith(\"$hostname\")) | .id" | head -1) || true
        if [[ -n "$old_id" ]]; then
            echo "Removing old device $old_id..."
            curl -s -X DELETE \
                -H "Authorization: Bearer $TAILSCALE_API_KEY" \
                "https://api.tailscale.com/api/v2/device/$old_id" || true
        fi
    fi

    # Register with tagged key
    echo "Registering with Tailscale..."
    sudo tailscale up \
        --authkey="$TAILSCALE_AUTH_KEY" \
        --ssh \
        --hostname="$hostname"

    echo "Tailscale registered as $hostname"

    # Cleanup auth keys immediately
    unset TAILSCALE_AUTH_KEY TAILSCALE_API_KEY
}

# Main setup
main() {
    persist_secrets
    setup_tailscale

    # Install and configure tools
    echo "Installing tools..."
    bash "$SCRIPT_DIR/install-tools.sh"

    echo "Configuring tools..."
    bash "$SCRIPT_DIR/configure-tools.sh"

    echo "=== Setup Complete ==="
}

main "$@"
