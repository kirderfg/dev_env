#!/bin/bash
# One-time setup when devcontainer is created
set -e

echo "========================================"
echo "  DevContainer Setup"
echo "========================================"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[Setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[Setup]${NC} $1"; }

# Install 1Password CLI for secure secret management
if ! command -v op &> /dev/null; then
    log "Installing 1Password CLI..."
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | sudo tee /etc/apt/sources.list.d/1password.list
    sudo apt-get update && sudo apt-get install -y 1password-cli
fi

# Save 1Password token FIRST (before any op commands that might fail)
# This ensures the token persists for shell sessions even if setup fails
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    log "Saving 1Password token for persistent access..."
    mkdir -p ~/.config/dev_env
    chmod 700 ~/.config/dev_env
    echo "$OP_SERVICE_ACCOUNT_TOKEN" > ~/.config/dev_env/op_token
    chmod 600 ~/.config/dev_env/op_token
fi

# Load secrets from 1Password for shell-bootstrap and later use
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    if op whoami &> /dev/null; then
        log "1Password CLI authenticated via service account"

        # Load secrets from 1Password
        log "Loading secrets from 1Password..."
        export ATUIN_USERNAME=$(op read "op://DEV_CLI/Atuin/username" 2>/dev/null) || true
        export ATUIN_PASSWORD=$(op read "op://DEV_CLI/Atuin/password" 2>/dev/null) || true
        export ATUIN_KEY=$(op read "op://DEV_CLI/Atuin/key" 2>/dev/null) || true
        export GITHUB_TOKEN=$(op read "op://DEV_CLI/GitHub/PAT" 2>/dev/null) || true
        export GH_TOKEN="$GITHUB_TOKEN"

        if [ -n "$ATUIN_USERNAME" ]; then
            log "Loaded Atuin credentials"
        fi
        if [ -n "$GITHUB_TOKEN" ]; then
            log "Loaded GitHub token"
        fi

        # Create op-secrets.sh for persistent secret loading in shell sessions
        log "Creating 1Password secrets loader..."
        cat > ~/.config/dev_env/op-secrets.sh << 'OPSECRETS'
#!/bin/bash
# 1Password secrets loader - source this file to load secrets on-demand

# Auto-load token from file if not in environment
if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ] && [ -f ~/.config/dev_env/op_token ]; then
    export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/dev_env/op_token)"
fi

op-check() {
    command -v op &>/dev/null && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]
}

op-load-secret() {
    local var_name="$1"
    local secret_ref="$2"
    if ! op-check 2>/dev/null; then return 1; fi
    local value=$(op read "$secret_ref" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$value" ]; then
        export "$var_name"="$value"
        return 0
    fi
    return 1
}

op-load-all-secrets() {
    if ! op-check; then return 1; fi
    local loaded=0
    op-load-secret GITHUB_TOKEN "op://DEV_CLI/GitHub/PAT" && loaded=$((loaded + 1))
    op-load-secret GH_TOKEN "op://DEV_CLI/GitHub/PAT" && loaded=$((loaded + 1))
    op-load-secret ATUIN_USERNAME "op://DEV_CLI/Atuin/username" && loaded=$((loaded + 1))
    op-load-secret ATUIN_PASSWORD "op://DEV_CLI/Atuin/password" && loaded=$((loaded + 1))
    op-load-secret ATUIN_KEY "op://DEV_CLI/Atuin/key" && loaded=$((loaded + 1))
    echo "[op-secrets] Loaded ${loaded} secrets" >&2
}

# Auto-load on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    op-load-all-secrets
fi
OPSECRETS
        chmod +x ~/.config/dev_env/op-secrets.sh

        # Create init.sh for shell startup
        cat > ~/.config/dev_env/init.sh << 'INITSH'
#!/bin/bash
# Source this in shell startup to load 1Password secrets
if [ -f ~/.config/dev_env/op_token ]; then
    export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/dev_env/op_token)"
fi
if [ -f ~/.config/dev_env/op-secrets.sh ]; then
    source ~/.config/dev_env/op-secrets.sh
fi
INITSH
        chmod +x ~/.config/dev_env/init.sh
    else
        warn "OP_SERVICE_ACCOUNT_TOKEN set but authentication failed"
    fi
else
    warn "OP_SERVICE_ACCOUNT_TOKEN not set - secrets won't be loaded automatically"
    warn "Pass it via: --workspace-env OP_SERVICE_ACCOUNT_TOKEN=\$(cat ~/.config/dev_env/op_token)"
fi

# Run shell-bootstrap for terminal tools (zsh, starship, atuin, yazi, glow, etc.)
# shell-bootstrap handles: op CLI install, 1Password setup, secrets loading
# SHELL_BOOTSTRAP_NONINTERACTIVE=1 is required for DevPod/CI environments
log "Running shell-bootstrap..."
curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/shell-bootstrap-install.sh
SHELL_BOOTSTRAP_NONINTERACTIVE=1 bash /tmp/shell-bootstrap-install.sh || warn "shell-bootstrap failed (non-fatal)"
rm -f /tmp/shell-bootstrap-install.sh

# Ensure PATH includes local bins (for atuin, pet, etc.)
export PATH="$HOME/.local/bin:$HOME/.atuin/bin:$PATH"

# Post shell-bootstrap: Configure Atuin login if credentials available
if [ -n "$ATUIN_USERNAME" ] && [ -n "$ATUIN_PASSWORD" ] && [ -n "$ATUIN_KEY" ]; then
    if command -v atuin &> /dev/null; then
        log "Logging into Atuin..."
        atuin login -u "$ATUIN_USERNAME" -p "$ATUIN_PASSWORD" -k "$ATUIN_KEY" 2>/dev/null && log "Atuin logged in" || warn "Atuin login failed"
        atuin sync 2>/dev/null || true
    fi
fi

# Install security scanning tools
log "Installing security tools..."
pip install --quiet safety bandit

# Install gitleaks for secret detection
if ! command -v gitleaks &> /dev/null; then
    log "Installing gitleaks..."
    curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.21.2/gitleaks_8.21.2_linux_x64.tar.gz | tar -xz -C /tmp
    sudo mv /tmp/gitleaks /usr/local/bin/
fi

# Install trivy for vulnerability scanning
if ! command -v trivy &> /dev/null; then
    log "Installing trivy..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin
fi

# Install Snyk CLI
if ! command -v snyk &> /dev/null; then
    log "Installing Snyk CLI..."
    npm install -g snyk
    warn "Run 'snyk auth' to authenticate with Snyk"
fi

# Install Tailscale for remote SSH access
if ! command -v tailscale &> /dev/null; then
    log "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Configure Tailscale if auth key available
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    TAILSCALE_AUTH_KEY=$(op read "op://DEV_CLI/Tailscale/auth_key" 2>/dev/null) || true
    TAILSCALE_API_KEY=$(op read "op://DEV_CLI/Tailscale/api_key" 2>/dev/null) || true
    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        log "Configuring Tailscale..."
        # Start tailscaled in userspace mode (works in containers without root)
        sudo tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock > /tmp/tailscaled.log 2>&1 &
        sleep 2
        # Get container/workspace name for hostname
        CONTAINER_NAME="${DEVCONTAINER_NAME:-$(basename $(pwd))}"
        TS_HOSTNAME="devpod-${CONTAINER_NAME}"

        # Remove existing Tailscale device with same hostname (if API key available)
        if [ -n "$TAILSCALE_API_KEY" ]; then
            log "Checking for existing Tailscale device: $TS_HOSTNAME..."
            EXISTING_DEVICE=$(curl -s -H "Authorization: Bearer $TAILSCALE_API_KEY" \
                "https://api.tailscale.com/api/v2/tailnet/-/devices" 2>/dev/null | \
                grep -o "\"id\":\"[^\"]*\",\"name\":\"$TS_HOSTNAME\"" | \
                head -1 | sed 's/.*"id":"\([^"]*\)".*/\1/')
            if [ -n "$EXISTING_DEVICE" ]; then
                log "Removing existing device: $TS_HOSTNAME ($EXISTING_DEVICE)..."
                curl -s -X DELETE -H "Authorization: Bearer $TAILSCALE_API_KEY" \
                    "https://api.tailscale.com/api/v2/device/$EXISTING_DEVICE" 2>/dev/null && \
                    log "Removed old device" || warn "Failed to remove old device"
                sleep 1
            fi
        fi

        sudo tailscale up --authkey="$TAILSCALE_AUTH_KEY" --ssh --hostname="$TS_HOSTNAME" --force-reauth && log "Tailscale connected!" || warn "Tailscale auth failed"
        if tailscale status &> /dev/null; then
            TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
            log "Tailscale IP: $TS_IP"
        fi
    else
        warn "Tailscale auth key not found in 1Password"
    fi
else
    warn "Tailscale not configured (no 1Password token)"
fi

# Install Python dependencies if pyproject.toml exists
if [ -f "pyproject.toml" ]; then
    log "Installing Python dependencies..."
    pip install --upgrade pip
    pip install -e ".[dev]" 2>/dev/null || pip install -e "." 2>/dev/null || true
fi

# Install Node dependencies if package.json exists
if [ -f "package.json" ]; then
    log "Installing Node dependencies..."
    npm install
fi

# Setup pre-commit hooks
if [ -f ".pre-commit-config.yaml" ]; then
    log "Installing pre-commit hooks..."
    pre-commit install
    pre-commit install --hook-type commit-msg 2>/dev/null || true
fi

# Configure git
log "Configuring git..."
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global fetch.prune true
git config --global credential.helper '!gh auth git-credential'

# Setup gh CLI with token if available
if [ -n "$GITHUB_TOKEN" ]; then
    if command -v gh &> /dev/null; then
        log "Configuring GitHub CLI..."
        echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null && log "GitHub CLI authenticated" || warn "GitHub CLI auth failed"
    fi
else
    if command -v gh &> /dev/null; then
        if ! gh auth status &> /dev/null; then
            warn "GitHub CLI not authenticated. Run: gh auth login"
        fi
    fi
fi

log "Setup complete!"
echo ""
