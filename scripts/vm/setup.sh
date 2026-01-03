#!/bin/bash
# Setup script for dev-vm
# Run this after cloning dev_env to the VM
#
# Usage:
#   git clone https://github.com/kirderfg/dev_env.git ~/dev_env
#   ~/dev_env/scripts/vm/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="setup"
source "$SCRIPT_DIR/../core/common.sh"

TOKEN_FILE="${HOME}/.config/dev_env/op_token"

log "=== Dev VM Setup ==="

# Prompt for 1Password token
setup_op_token() {
    # Check if token already exists
    if [[ -f "$TOKEN_FILE" ]]; then
        info "Token file already exists at $TOKEN_FILE"
        if ! confirm "Overwrite?"; then
            log "Keeping existing token."
            return 0
        fi
        rm -f "$TOKEN_FILE"
    fi

    # Prompt for token
    echo "Enter your 1Password Service Account Token"
    echo "(paste and press Enter - input is hidden):"
    echo ""
    read -s -r OP_TOKEN
    echo ""

    if [[ -z "$OP_TOKEN" ]]; then
        error "No token provided"
        exit 1
    fi

    # Save token
    mkdir -p "$(dirname "$TOKEN_FILE")"
    echo "$OP_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    log "Token saved to $TOKEN_FILE"
}

# Verify 1Password authentication
verify_op_auth() {
    # Export token for this session
    export OP_SERVICE_ACCOUNT_TOKEN="$(cat "$TOKEN_FILE")"

    log "Verifying 1Password authentication..."
    if ! command -v op &> /dev/null; then
        error "1Password CLI not installed. Installing tools first..."
        return 1
    fi

    if ! op whoami &>/dev/null; then
        error "1Password authentication failed. Check your token."
        rm -f "$TOKEN_FILE"
        exit 1
    fi
    log "1Password authenticated successfully"
}

# Main setup
main() {
    # Step 1: Setup 1Password token
    setup_op_token

    # Step 2: Install tools (only if 1Password not available)
    if ! command -v op &> /dev/null; then
        log "Installing tools..."
        "$SCRIPT_DIR/install-tools.sh"
    else
        info "Tools already installed. Run scripts/vm/install-tools.sh to reinstall."
    fi

    # Step 3: Verify 1Password works
    verify_op_auth

    # Step 4: Configure tools with secrets
    log "Configuring tools..."
    "$SCRIPT_DIR/configure-tools.sh"

    # Step 5: Run shell-bootstrap if not already done
    if [[ ! -f "$HOME/.config/shell-bootstrap/zshrc" ]]; then
        log "Running shell-bootstrap..."
        curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/shell-bootstrap-install.sh
        SHELL_BOOTSTRAP_NONINTERACTIVE=1 bash /tmp/shell-bootstrap-install.sh
        rm -f /tmp/shell-bootstrap-install.sh
    else
        info "shell-bootstrap already installed"
    fi

    log "=== Setup Complete ==="
    echo ""
    echo "Start a new shell or run: exec zsh"
    echo ""
    echo "Then use devpods with:"
    echo "  ~/dev_env/scripts/devpod/dp.sh up https://github.com/user/repo"
    echo ""
}

main "$@"
