#!/bin/bash
# Azure Cloud Shell Bootstrap Script
#
# This script sets up a persistent development environment in Azure Cloud Shell.
# It installs tools to ~/clouddrive which persists across sessions.
#
# Note: Azure Files (backing ~/clouddrive) doesn't support symlinks, so we use
# wrapper scripts instead of npm's default global installs.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kirderfg/dev_env/main/scripts/cloudshell/setup.sh | bash
#
# Or if you've already cloned:
#   ~/clouddrive/dev_env/scripts/cloudshell/setup.sh

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
PERSISTENT_NPM_PACKAGES="$HOME/clouddrive/.npm-packages"
PERSISTENT_DEV_ENV="$HOME/clouddrive/dev_env"
BASHRC="$HOME/.bashrc"
MARKER="# >>> dev_env cloudshell bootstrap >>>"
END_MARKER="# <<< dev_env cloudshell bootstrap <<<"

echo "Setting up persistent directories..."
mkdir -p "$PERSISTENT_BIN"
mkdir -p "$PERSISTENT_NPM_PACKAGES"

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
# Persistent bin directory (includes wrapper scripts for npm packages)
export PATH="$HOME/clouddrive/bin:$PATH"

# Source dev_env helpers if present
if [ -f "$HOME/clouddrive/dev_env/scripts/cloudshell/helpers.sh" ]; then
    source "$HOME/clouddrive/dev_env/scripts/cloudshell/helpers.sh"
fi
# <<< dev_env cloudshell bootstrap <<<
BASHRCEOF
}

# Add/update .bashrc configuration
add_bashrc_block

# Export for current session
export PATH="$PERSISTENT_BIN:$PATH"

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

# Check Node.js version and install newer if needed
echo ""
echo "Checking Node.js version..."
NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
REQUIRED_NODE_VERSION=18

if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" -lt "$REQUIRED_NODE_VERSION" ]; then
    echo "Node.js v$NODE_VERSION is too old. Claude Code requires Node.js $REQUIRED_NODE_VERSION+."
    echo "Installing Node.js 20.x to persistent storage..."

    NODE_DIR="$HOME/clouddrive/.node"
    mkdir -p "$NODE_DIR"

    # Download and extract Node.js
    NODE_DIST_VERSION="20.18.0"
    if [ ! -x "$NODE_DIR/bin/node" ]; then
        curl -sL "https://nodejs.org/dist/v${NODE_DIST_VERSION}/node-v${NODE_DIST_VERSION}-linux-x64.tar.xz" | tar -xJ -C "$NODE_DIR" --strip-components=1
        echo -e "${GREEN}Node.js v${NODE_DIST_VERSION} installed to $NODE_DIR${NC}"
    fi

    # Add to PATH for this session and future sessions
    export PATH="$NODE_DIR/bin:$PATH"

    # Update bashrc block to include node path
    if ! grep -q "clouddrive/.node/bin" "$BASHRC" 2>/dev/null; then
        sed -i "s|export PATH=\"\$HOME/clouddrive/bin:\$PATH\"|export PATH=\"\$HOME/clouddrive/.node/bin:\$HOME/clouddrive/bin:\$PATH\"|" "$BASHRC"
    fi

    echo "Node.js $(node --version) now active"
else
    echo "Node.js v$NODE_VERSION is sufficient"
fi

# Install Claude Code CLI
# Azure Files doesn't support symlinks, so we install the package and create a wrapper script
echo ""
echo "Installing Claude Code CLI..."
CLAUDE_PKG_DIR="$PERSISTENT_NPM_PACKAGES/claude-code"

install_claude() {
    echo "Installing @anthropic-ai/claude-code package..."
    rm -rf "$CLAUDE_PKG_DIR"
    mkdir -p "$CLAUDE_PKG_DIR"

    # Install package to a local directory (no symlinks needed)
    cd "$CLAUDE_PKG_DIR"
    npm init -y > /dev/null 2>&1 || true

    echo "Running npm install (this may take a minute)..."
    # Use --no-bin-links because Azure Files doesn't support symlinks
    if ! npm install @anthropic-ai/claude-code --save --no-bin-links 2>&1; then
        echo -e "${RED}npm install failed${NC}"
        cd - > /dev/null
        return 1
    fi

    # Verify the package was installed
    if [ ! -d "$CLAUDE_PKG_DIR/node_modules/@anthropic-ai/claude-code" ]; then
        echo -e "${RED}Package directory not found after install${NC}"
        cd - > /dev/null
        return 1
    fi

    # Create wrapper script that calls node directly
    cat > "$PERSISTENT_BIN/claude" << 'WRAPPER_EOF'
#!/bin/bash
# Wrapper script for Claude Code CLI
# Azure Files doesn't support symlinks, so we call node directly
SCRIPT_DIR="$HOME/clouddrive/.npm-packages/claude-code"
# Use persistent node if available, otherwise system node
if [ -x "$HOME/clouddrive/.node/bin/node" ]; then
    NODE_BIN="$HOME/clouddrive/.node/bin/node"
else
    NODE_BIN="node"
fi
NODE_PATH="$SCRIPT_DIR/node_modules" exec "$NODE_BIN" "$SCRIPT_DIR/node_modules/@anthropic-ai/claude-code/cli.js" "$@"
WRAPPER_EOF
    chmod +x "$PERSISTENT_BIN/claude"
    echo -e "${GREEN}Claude Code wrapper created${NC}"

    cd - > /dev/null
}

if [ -x "$PERSISTENT_BIN/claude" ] && [ -d "$CLAUDE_PKG_DIR/node_modules/@anthropic-ai/claude-code" ]; then
    # Verify it works
    if CLAUDE_VERSION=$("$PERSISTENT_BIN/claude" --version 2>/dev/null | head -1); then
        echo "Claude Code CLI already installed ($CLAUDE_VERSION)"
    else
        echo "Claude installation appears broken, reinstalling..."
        install_claude
    fi
else
    install_claude
fi

# Verify Claude installation
if [ -x "$PERSISTENT_BIN/claude" ]; then
    if CLAUDE_VERSION=$("$PERSISTENT_BIN/claude" --version 2>/dev/null | head -1); then
        echo -e "${GREEN}Claude Code CLI installed ($CLAUDE_VERSION)${NC}"
    else
        echo -e "${YELLOW}Claude Code CLI installed but may need shell restart${NC}"
    fi
else
    echo -e "${RED}Claude Code CLI installation failed${NC}"
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

# Create convenience symlink (in home dir, not clouddrive, so symlinks work)
if [ ! -L "$HOME/dev_env" ] && [ ! -d "$HOME/dev_env" ]; then
    ln -s "$PERSISTENT_DEV_ENV" "$HOME/dev_env" 2>/dev/null || true
    echo "Created symlink: ~/dev_env -> $PERSISTENT_DEV_ENV"
fi

echo ""
echo -e "${GREEN}=== Bootstrap Complete ===${NC}"
echo ""
echo "Installed to persistent storage (~/clouddrive):"
echo "  - 1Password CLI: $PERSISTENT_BIN/op"
echo "  - Claude Code CLI: $PERSISTENT_BIN/claude"
echo "  - dev_env: $PERSISTENT_DEV_ENV"
echo ""
echo "PATH configured in ~/.bashrc - changes persist across sessions."
echo ""
echo -e "${YELLOW}To use immediately, run:${NC}"
echo "  source ~/.bashrc"
echo ""
echo -e "${YELLOW}Next steps for VM deployment:${NC}"
echo "  cd ~/clouddrive/dev_env"
echo "  ./scripts/azure/deploy.sh"
echo ""
