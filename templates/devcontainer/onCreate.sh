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

# Verify 1Password service account is configured and load secrets
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    if op whoami &> /dev/null; then
        log "1Password CLI authenticated via service account"

        # Load secrets from 1Password for shell-bootstrap
        log "Loading secrets from 1Password..."
        export ATUIN_USERNAME=$(op read "op://DEV_CLI/Atuin/username" 2>/dev/null) || true
        export ATUIN_PASSWORD=$(op read "op://DEV_CLI/Atuin/password" 2>/dev/null) || true
        export ATUIN_KEY=$(op read "op://DEV_CLI/Atuin/key" 2>/dev/null) || true
        export PET_SNIPPETS_TOKEN=$(op read "op://DEV_CLI/Pet/PAT" 2>/dev/null) || true
        export OPENAI_API_KEY=$(op read "op://DEV_CLI/OpenAI/api_key" 2>/dev/null) || true
        export GITHUB_TOKEN=$(op read "op://DEV_CLI/GitHub/PAT" 2>/dev/null) || true

        if [ -n "$ATUIN_USERNAME" ]; then
            log "Loaded Atuin credentials"
        fi
        if [ -n "$PET_SNIPPETS_TOKEN" ]; then
            log "Loaded Pet snippets token"
        fi
    else
        warn "OP_SERVICE_ACCOUNT_TOKEN set but authentication failed"
    fi
else
    warn "OP_SERVICE_ACCOUNT_TOKEN not set - secrets won't be available"
    warn "Set it in DevPod: devpod provider update ssh -o OP_SERVICE_ACCOUNT_TOKEN=<token>"
fi

# Run shell-bootstrap for terminal tools (zsh, starship, atuin, yazi, glow, etc.)
# NOTE: Must download first then run - piping to bash breaks interactive prompts
# Secrets are already in environment from 1Password above
log "Running shell-bootstrap..."
curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/shell-bootstrap-install.sh
bash /tmp/shell-bootstrap-install.sh || warn "shell-bootstrap failed (non-fatal)"
rm -f /tmp/shell-bootstrap-install.sh

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

# Setup gh CLI if not authenticated
if command -v gh &> /dev/null; then
    if ! gh auth status &> /dev/null; then
        warn "GitHub CLI not authenticated. Run: gh auth login"
    fi
fi

log "Setup complete!"
echo ""
