#!/bin/bash
# Configure tools using 1Password secrets
# Run this after install-tools.sh and setting up the 1Password token

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="configure-tools"
source "$SCRIPT_DIR/../core/common.sh"
source "$SCRIPT_DIR/../core/secrets.sh"

log "Starting tool configuration..."

# Ensure 1Password token is available
if ! load_op_token; then
    error "1Password token not found. Run setup.sh first to configure the token."
    exit 1
fi

# Verify 1Password works
if ! op whoami &>/dev/null; then
    error "1Password authentication failed. Check your token."
    exit 1
fi
log "1Password authenticated"

# Read all secrets
read_all_secrets

# Configure GitHub CLI
configure_github() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        warn "GITHUB_TOKEN not set, skipping GitHub CLI configuration"
        return 0
    fi

    log "Configuring GitHub CLI..."
    echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || {
        warn "GitHub CLI auth failed"
        return 0
    }
    gh auth setup-git 2>/dev/null || true
    log "GitHub CLI configured"
}

# Configure Atuin shell history
configure_atuin() {
    if [[ -z "$ATUIN_USERNAME" || -z "$ATUIN_PASSWORD" ]]; then
        warn "Atuin credentials not set, skipping configuration"
        return 0
    fi

    if ! command -v atuin &> /dev/null; then
        warn "Atuin not installed, skipping configuration"
        return 0
    fi

    log "Configuring Atuin..."
    # Login to Atuin
    if [[ -n "$ATUIN_KEY" ]]; then
        echo "$ATUIN_PASSWORD" | atuin login -u "$ATUIN_USERNAME" --key "$ATUIN_KEY" 2>/dev/null || {
            warn "Atuin login failed"
            return 0
        }
    else
        echo "$ATUIN_PASSWORD" | atuin login -u "$ATUIN_USERNAME" 2>/dev/null || {
            warn "Atuin login failed"
            return 0
        }
    fi
    log "Atuin configured"
}

# Configure Pet snippets
configure_pet() {
    if [[ -z "$PET_GITHUB_TOKEN" ]]; then
        warn "PET_GITHUB_TOKEN not set, skipping Pet configuration"
        return 0
    fi

    if ! command -v pet &> /dev/null; then
        warn "Pet not installed, skipping configuration"
        return 0
    fi

    log "Configuring Pet snippets..."
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
    pet sync 2>/dev/null || warn "Pet sync failed (this is normal for first run)"
    log "Pet configured"
}

# Configure MCP for Claude Code
configure_mcp() {
    log "Configuring Task Master MCP for Claude Code..."
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
    log "MCP config created at $mcp_config"
}

# Configure DevPod docker provider
configure_devpod() {
    if ! command -v devpod &> /dev/null; then
        warn "DevPod not installed, skipping configuration"
        return 0
    fi

    log "Configuring DevPod docker provider..."
    devpod provider add docker 2>/dev/null || true
    devpod provider use docker 2>/dev/null || true
    log "DevPod docker provider configured"
}

# Main configuration
main() {
    configure_github
    configure_atuin
    configure_pet
    configure_mcp
    configure_devpod

    log "All tools configured successfully"
    info "Start a new shell or run: exec zsh"
}

main "$@"
