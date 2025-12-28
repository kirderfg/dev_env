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
