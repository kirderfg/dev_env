#!/bin/bash
# Bootstrap script for Azure Cloud Shell
# Usage: OP_SERVICE_ACCOUNT_TOKEN=xxx bash bootstrap.sh
#
# This script:
# 1. Installs 1Password CLI if needed
# 2. Fetches GitHub PAT from 1Password
# 3. Clones the dev_env repo
# 4. Runs setup.sh to deploy the VM

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[bootstrap]${NC} $1"; }
warn() { echo -e "${YELLOW}[bootstrap]${NC} $1"; }
error() { echo -e "${RED}[bootstrap]${NC} $1" >&2; }

# Check for OP token
if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    error "OP_SERVICE_ACCOUNT_TOKEN environment variable is required"
    echo ""
    echo "Usage:"
    echo "  export OP_SERVICE_ACCOUNT_TOKEN='your-token'"
    echo "  bash bootstrap.sh"
    echo ""
    echo "Or as one-liner:"
    echo "  OP_SERVICE_ACCOUNT_TOKEN='your-token' bash bootstrap.sh"
    exit 1
fi

export OP_SERVICE_ACCOUNT_TOKEN

# Install 1Password CLI if not present
if ! command -v op &> /dev/null; then
    log "Installing 1Password CLI..."

    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  OP_ARCH="amd64" ;;
        aarch64) OP_ARCH="arm64" ;;
        arm64)   OP_ARCH="arm64" ;;
        *)
            error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    # Download and install to ~/bin (works in Cloud Shell)
    mkdir -p ~/bin
    curl -sSfLo /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/v2.30.0/op_linux_${OP_ARCH}_v2.30.0.zip"
    unzip -o -q /tmp/op.zip -d /tmp/op_extracted
    mv /tmp/op_extracted/op ~/bin/op
    chmod +x ~/bin/op
    rm -rf /tmp/op.zip /tmp/op_extracted

    # Add to PATH for this session
    export PATH="$HOME/bin:$PATH"

    log "1Password CLI installed to ~/bin/op"
fi

# Verify 1Password works
log "Verifying 1Password authentication..."
if ! op whoami &>/dev/null; then
    error "1Password authentication failed. Check your OP_SERVICE_ACCOUNT_TOKEN."
    exit 1
fi
log "1Password authenticated successfully"

# Save OP token for later use
mkdir -p ~/.config/dev_env
echo "$OP_SERVICE_ACCOUNT_TOKEN" > ~/.config/dev_env/op_token
chmod 600 ~/.config/dev_env/op_token
log "Saved OP token to ~/.config/dev_env/op_token"

# Get GitHub PAT and authenticate
log "Fetching GitHub PAT from 1Password..."
GITHUB_PAT=$(op read "op://DEV_CLI/GitHub/PAT")
if [ -z "$GITHUB_PAT" ]; then
    error "Failed to read GitHub PAT from 1Password"
    error "Make sure op://DEV_CLI/GitHub/PAT exists"
    exit 1
fi

# Install GitHub CLI if not present (Cloud Shell has it, but just in case)
if ! command -v gh &> /dev/null; then
    log "Installing GitHub CLI..."
    mkdir -p ~/bin
    curl -sSfL https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_linux_amd64.tar.gz | tar xz -C /tmp
    mv /tmp/gh_2.63.2_linux_amd64/bin/gh ~/bin/gh
    chmod +x ~/bin/gh
    rm -rf /tmp/gh_2.63.2_linux_amd64
fi

# Authenticate GitHub CLI
log "Authenticating GitHub CLI..."
echo "$GITHUB_PAT" | gh auth login --with-token
gh auth setup-git
log "GitHub CLI authenticated"

# Clone dev_env if not exists
DEV_ENV_DIR="$HOME/dev_env"
if [ -d "$DEV_ENV_DIR" ]; then
    log "dev_env already exists at $DEV_ENV_DIR"
    cd "$DEV_ENV_DIR"
    git pull --ff-only || true
else
    log "Cloning dev_env repository..."
    git clone https://github.com/kirderfg/dev_env.git "$DEV_ENV_DIR"
    cd "$DEV_ENV_DIR"
fi

log "Running setup.sh..."
echo ""
./setup.sh
