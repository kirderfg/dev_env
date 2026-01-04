#!/bin/bash
# DevPod container one-time setup
# Secrets are injected as environment variables by dp.sh
# NO 1Password CLI installed - secrets come from env vars

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== DevPod Container Setup ==="

# Get workspace root directory
get_workspace_root() {
    if [[ -d "/workspaces" ]]; then
        # DevPod puts workspaces in /workspaces/<name>
        find /workspaces -maxdepth 1 -type d ! -name workspaces | head -1
    else
        # Fallback to parent of .devcontainer
        dirname "$SCRIPT_DIR"
    fi
}

# Run a local hook script if it exists
# Usage: run_local_hook "setup.sh" "setup"
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
        # Source the hook so it has access to our functions and variables
        source "$hook_path"
    fi
}

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

# Install project dependencies
install_project_deps() {
    echo "Installing project dependencies..."

    local workspace_root
    workspace_root="$(get_workspace_root)"

    if [[ -z "$workspace_root" || ! -d "$workspace_root" ]]; then
        echo "Could not determine workspace root, skipping dependency installation"
        return 0
    fi

    echo "Workspace root: $workspace_root"
    cd "$workspace_root"

    # Python dependencies - check multiple locations
    if [[ -f "requirements.txt" ]]; then
        echo "Installing Python dependencies from requirements.txt..."
        pip install --upgrade pip
        pip install -r requirements.txt
    elif [[ -f "backend/requirements.txt" ]]; then
        echo "Installing Python dependencies from backend/requirements.txt..."
        pip install --upgrade pip
        pip install -r backend/requirements.txt
        # Also install test requirements if they exist
        if [[ -f "backend/requirements-test.txt" ]]; then
            pip install -r backend/requirements-test.txt
        fi
    fi

    if [[ -f "pyproject.toml" ]]; then
        echo "Installing Python package from pyproject.toml..."
        pip install --upgrade pip
        pip install -e ".[dev]" 2>/dev/null || pip install -e "." 2>/dev/null || true
    fi

    # Node dependencies
    if [[ -f "package.json" ]]; then
        echo "Installing Node dependencies from package.json..."
        npm install
    fi

    # Check for frontend directory with its own package.json
    for frontend_dir in frontend frontend-svelte client; do
        if [[ -f "$frontend_dir/package.json" ]]; then
            echo "Installing Node dependencies from $frontend_dir/package.json..."
            (cd "$frontend_dir" && npm install)
        fi
    done

    echo "Project dependencies installed"
}

# Main setup
main() {
    # Run pre-setup hook (before any template setup)
    run_local_hook "pre-setup.sh" "pre-setup"

    persist_secrets
    setup_tailscale

    # Install and configure tools
    echo "Installing tools..."
    bash "$SCRIPT_DIR/install-tools.sh"

    echo "Configuring tools..."
    bash "$SCRIPT_DIR/configure-tools.sh"

    # Install project-specific dependencies
    install_project_deps

    # Run post-setup hook (for repo-specific setup like Stockfish)
    run_local_hook "setup.sh" "post-setup"

    echo "=== Setup Complete ==="
}

main "$@"
