#!/bin/bash
# Configure tools from environment variables
# NO 1Password - secrets come from env vars injected by dp.sh

set -e

echo "Configuring tools..."

# Source persisted secrets if available
if [[ -f ~/.config/dev_env/secrets.sh ]]; then
    source ~/.config/dev_env/secrets.sh
fi

# Configure GitHub CLI
configure_github() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "GITHUB_TOKEN not set, skipping GitHub CLI configuration"
        return 0
    fi

    echo "Configuring GitHub CLI..."
    echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || {
        echo "GitHub CLI auth failed"
        return 0
    }
    gh auth setup-git 2>/dev/null || true
    echo "GitHub CLI configured"
}

# Configure Atuin shell history
configure_atuin() {
    if [[ -z "$ATUIN_USERNAME" || -z "$ATUIN_PASSWORD" ]]; then
        echo "Atuin credentials not set, skipping configuration"
        return 0
    fi

    if ! command -v atuin &> /dev/null; then
        echo "Atuin not installed, skipping configuration"
        return 0
    fi

    echo "Configuring Atuin..."
    if [[ -n "$ATUIN_KEY" ]]; then
        echo "$ATUIN_PASSWORD" | atuin login -u "$ATUIN_USERNAME" --key "$ATUIN_KEY" 2>/dev/null || {
            echo "Atuin login failed"
            return 0
        }
    else
        echo "$ATUIN_PASSWORD" | atuin login -u "$ATUIN_USERNAME" 2>/dev/null || {
            echo "Atuin login failed"
            return 0
        }
    fi
    echo "Atuin configured"
}

# Configure Pet snippets
configure_pet() {
    if [[ -z "$PET_GITHUB_TOKEN" ]]; then
        echo "PET_GITHUB_TOKEN not set, skipping Pet configuration"
        return 0
    fi

    if ! command -v pet &> /dev/null; then
        echo "Pet not installed, skipping configuration"
        return 0
    fi

    echo "Configuring Pet snippets..."
    mkdir -p ~/.config/pet
    cat > ~/.config/pet/config.toml << EOF
[General]
snippetfile = "$HOME/.config/pet/snippet.toml"
editor = "vim"
backend = "gist"

[Gist]
access_token = "$PET_GITHUB_TOKEN"
auto_sync = true
EOF
    chmod 600 ~/.config/pet/config.toml
    pet sync 2>/dev/null || echo "Pet sync failed (this is normal for first run)"
    echo "Pet configured"
}

# Configure MCP for Claude Code
configure_mcp() {
    echo "Configuring Task Master MCP for Claude Code..."
    local mcp_config="${HOME}/.claude/.mcp.json"

    mkdir -p "${HOME}/.claude"
    cat > "$mcp_config" << 'EOF'
{
  "mcpServers": {
    "taskmaster-ai": {
      "command": "npx",
      "args": ["-y", "--package=task-master-ai", "task-master-ai"]
    }
  }
}
EOF
    echo "MCP config created"
}

# Main configuration
main() {
    configure_github
    configure_atuin
    configure_pet
    configure_mcp

    echo "All tools configured"
}

main "$@"
