#!/bin/bash
# Azure Cloud Shell Bootstrap Script
#
# This script sets up a persistent development environment in Azure Cloud Shell.
# It installs tools to ~/clouddrive which persists across sessions.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kirderfg/dev_env/main/scripts/setup-cloudshell.sh | bash
#
# Or if you've already cloned:
#   ~/clouddrive/dev_env/scripts/setup-cloudshell.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Azure Cloud Shell Bootstrap ===${NC}"
echo ""

# Check if running in Azure Cloud Shell
if [ -z "$AZURE_HTTP_USER_AGENT" ] && [ ! -d ~/clouddrive ]; then
    echo -e "${RED}Error: This script is designed for Azure Cloud Shell.${NC}"
    echo "It requires ~/clouddrive for persistent storage."
    exit 1
fi

# Persistent directories
PERSISTENT_BIN="$HOME/clouddrive/bin"
PERSISTENT_NPM_PREFIX="$HOME/clouddrive/.npm-global"
PERSISTENT_DEV_ENV="$HOME/clouddrive/dev_env"
BASHRC="$HOME/.bashrc"
MARKER="# >>> dev_env cloudshell bootstrap >>>"
END_MARKER="# <<< dev_env cloudshell bootstrap <<<"

echo "Setting up persistent directories..."
mkdir -p "$PERSISTENT_BIN"
mkdir -p "$PERSISTENT_NPM_PREFIX"

# Function to add block to .bashrc if not present
add_bashrc_block() {
    if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
        echo "Updating existing PATH configuration in .bashrc..."
        # Remove old block and add new one
        sed -i "/$MARKER/,/$END_MARKER/d" "$BASHRC"
    else
        echo "Adding PATH configuration to .bashrc..."
    fi

    cat >> "$BASHRC" << 'BASHRCEOF'
# >>> dev_env cloudshell bootstrap >>>
# Persistent bin directory
export PATH="$HOME/clouddrive/bin:$PATH"

# npm global packages in persistent location
export NPM_CONFIG_PREFIX="$HOME/clouddrive/.npm-global"
export PATH="$HOME/clouddrive/.npm-global/bin:$PATH"

# Source dev_env helpers if present
if [ -f "$HOME/clouddrive/dev_env/scripts/cloudshell-helpers.sh" ]; then
    source "$HOME/clouddrive/dev_env/scripts/cloudshell-helpers.sh"
fi
# <<< dev_env cloudshell bootstrap <<<
BASHRCEOF
}

# Add/update .bashrc configuration
add_bashrc_block

# Export for current session
export PATH="$PERSISTENT_BIN:$PATH"
export NPM_CONFIG_PREFIX="$PERSISTENT_NPM_PREFIX"
export PATH="$PERSISTENT_NPM_PREFIX/bin:$PATH"

# Configure npm to use persistent prefix
echo ""
echo "Configuring npm for persistent global packages..."
npm config set prefix "$PERSISTENT_NPM_PREFIX"

# Upgrade npm to latest
echo ""
echo "Upgrading npm to latest version..."
CURRENT_NPM=$(npm --version)
echo "Current npm version: $CURRENT_NPM"

# Install latest npm to the persistent prefix
npm install -g npm@latest 2>/dev/null || {
    echo -e "${YELLOW}Warning: npm upgrade had issues, continuing...${NC}"
}

# Use the newly installed npm
if [ -x "$PERSISTENT_NPM_PREFIX/bin/npm" ]; then
    export PATH="$PERSISTENT_NPM_PREFIX/bin:$PATH"
    NEW_NPM=$("$PERSISTENT_NPM_PREFIX/bin/npm" --version)
    echo -e "${GREEN}npm upgraded to: $NEW_NPM${NC}"
else
    NEW_NPM=$(npm --version)
    echo "npm version: $NEW_NPM"
fi

# Install 1Password CLI
echo ""
echo "Installing 1Password CLI..."
if [ -x "$PERSISTENT_BIN/op" ]; then
    OP_VERSION=$("$PERSISTENT_BIN/op" --version 2>/dev/null || echo "unknown")
    echo "1Password CLI already installed (version: $OP_VERSION)"
else
    OP_VERSION="2.30.0"
    curl -sSfLo /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_amd64_v${OP_VERSION}.zip"
    unzip -o -q /tmp/op.zip -d /tmp/op_extracted
    mv /tmp/op_extracted/op "$PERSISTENT_BIN/op"
    chmod +x "$PERSISTENT_BIN/op"
    rm -rf /tmp/op.zip /tmp/op_extracted
    echo -e "${GREEN}1Password CLI v${OP_VERSION} installed to $PERSISTENT_BIN/op${NC}"
fi

# Install Claude Code CLI
echo ""
echo "Installing Claude Code CLI..."
if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 || echo "installed")
    echo "Claude Code CLI already installed ($CLAUDE_VERSION)"
else
    npm install -g @anthropic-ai/claude-code
    if command -v claude &> /dev/null; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 || echo "installed")
        echo -e "${GREEN}Claude Code CLI installed ($CLAUDE_VERSION)${NC}"
    else
        echo -e "${YELLOW}Claude Code CLI installed. Restart shell or run: source ~/.bashrc${NC}"
    fi
fi

# Clone dev_env to persistent location if not present
echo ""
if [ -d "$PERSISTENT_DEV_ENV/.git" ]; then
    echo "dev_env already cloned to $PERSISTENT_DEV_ENV"
    echo "Pulling latest changes..."
    (cd "$PERSISTENT_DEV_ENV" && git pull --ff-only 2>/dev/null || echo "Could not pull, continuing with existing version")
else
    echo "Cloning dev_env to persistent location..."
    git clone https://github.com/kirderfg/dev_env.git "$PERSISTENT_DEV_ENV"
    echo -e "${GREEN}dev_env cloned to $PERSISTENT_DEV_ENV${NC}"
fi

# Create convenience symlink
if [ ! -L "$HOME/dev_env" ] && [ ! -d "$HOME/dev_env" ]; then
    ln -s "$PERSISTENT_DEV_ENV" "$HOME/dev_env"
    echo "Created symlink: ~/dev_env -> $PERSISTENT_DEV_ENV"
fi

echo ""
echo -e "${GREEN}=== Bootstrap Complete ===${NC}"
echo ""
echo "Installed to persistent storage (~/clouddrive):"
echo "  - 1Password CLI: $PERSISTENT_BIN/op"
echo "  - Claude Code CLI: $PERSISTENT_NPM_PREFIX/bin/claude"
echo "  - npm globals: $PERSISTENT_NPM_PREFIX"
echo "  - dev_env: $PERSISTENT_DEV_ENV"
echo ""
echo "PATH configured in ~/.bashrc - changes persist across sessions."
echo ""
echo -e "${YELLOW}To use immediately, run:${NC}"
echo "  source ~/.bashrc"
echo ""
echo -e "${YELLOW}Next steps for VM deployment:${NC}"
echo "  cd ~/clouddrive/dev_env"
echo "  ./scripts/deploy.sh"
echo ""
