#!/bin/bash
# Setup script for dev-vm
# Run this after cloning dev_env to the VM
#
# Usage:
#   git clone https://github.com/kirderfg/dev_env.git ~/dev_env
#   ~/dev_env/scripts/setup-vm.sh

set -e

TOKEN_FILE="${HOME}/.config/dev_env/op_token"

echo "=== Dev VM Setup ==="
echo ""

# Check if token already exists
if [ -f "$TOKEN_FILE" ]; then
    echo "Token file already exists at $TOKEN_FILE"
    read -p "Overwrite? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing token."
    else
        rm -f "$TOKEN_FILE"
    fi
fi

# Prompt for token if not exists
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Enter your 1Password Service Account Token"
    echo "(paste and press Enter - input is hidden):"
    echo ""
    read -s -r OP_TOKEN
    echo ""

    if [ -z "$OP_TOKEN" ]; then
        echo "Error: No token provided"
        exit 1
    fi

    # Save token
    mkdir -p "$(dirname "$TOKEN_FILE")"
    echo "$OP_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "Token saved to $TOKEN_FILE"
fi

# Export token for this session
export OP_SERVICE_ACCOUNT_TOKEN="$(cat "$TOKEN_FILE")"

# Verify 1Password works
echo ""
echo "Verifying 1Password authentication..."
if ! command -v op &> /dev/null; then
    echo "Error: 1Password CLI not installed. Run shell-bootstrap first."
    exit 1
fi

if ! op whoami &>/dev/null; then
    echo "Error: 1Password authentication failed. Check your token."
    rm -f "$TOKEN_FILE"
    exit 1
fi
echo "1Password authenticated successfully"

# Install Node.js 20.x for Task Master and npm packages
echo ""
echo "Installing Node.js 20.x..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "Node.js $(node --version) installed"
else
    echo "Node.js $(node --version) already installed"
fi

# Install Task Master globally
echo ""
echo "Installing Task Master..."
if ! command -v task-master &> /dev/null; then
    sudo npm install -g task-master-ai
    echo "Task Master installed"
else
    echo "Task Master already installed"
fi

# Create MCP config for Claude Code
echo ""
echo "Configuring Task Master MCP for Claude Code..."
MCP_CONFIG="${HOME}/.claude/.mcp.json"
if [ ! -f "$MCP_CONFIG" ]; then
    mkdir -p "${HOME}/.claude"
    cat > "$MCP_CONFIG" << 'MCPEOF'
{
  "mcpServers": {
    "taskmaster-ai": {
      "command": "npx",
      "args": ["-y", "--package=task-master-ai", "task-master-ai"]
    }
  }
}
MCPEOF
    echo "MCP config created at $MCP_CONFIG"
else
    echo "MCP config already exists"
fi

# Run shell-bootstrap to configure gh/atuin/git/pet
echo ""
echo "Running shell-bootstrap to configure gh, atuin, git, pet..."
curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/shell-bootstrap-install.sh
SHELL_BOOTSTRAP_NONINTERACTIVE=1 bash /tmp/shell-bootstrap-install.sh
rm -f /tmp/shell-bootstrap-install.sh

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Start a new shell or run: exec zsh"
echo ""
echo "Then use devpods with:"
echo "  ~/dev_env/scripts/dp.sh up https://github.com/user/repo"
echo ""
