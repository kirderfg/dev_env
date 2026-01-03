#!/bin/bash
# Secret reading functions - VM ONLY
# DO NOT source this file in devpod containers - secrets are injected via env vars
#
# This file provides functions to read secrets from 1Password on the VM.
# The dp.sh script uses these to inject secrets as environment variables
# when creating devpod workspaces.

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 1Password token file location
OP_TOKEN_FILE="${HOME}/.config/dev_env/op_token"

# Load 1Password service account token
load_op_token() {
    if [[ -f "$OP_TOKEN_FILE" ]]; then
        export OP_SERVICE_ACCOUNT_TOKEN=$(cat "$OP_TOKEN_FILE")
        if [[ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]]; then
            return 0
        fi
    fi
    warn "1Password token not found at $OP_TOKEN_FILE"
    return 1
}

# Read a single secret from 1Password
read_secret() {
    local path="$1"
    op read "$path" 2>/dev/null || echo ""
}

# Read all required secrets from 1Password
read_all_secrets() {
    if ! load_op_token; then
        warn "Secrets won't be available"
        return 1
    fi

    log "Reading secrets from 1Password..."

    # GitHub token (for git auth and gh CLI)
    GITHUB_TOKEN=$(read_secret "op://DEV_CLI/GitHub/PAT")
    if [[ -n "$GITHUB_TOKEN" ]]; then
        log "  - GitHub token loaded"
    fi

    # Atuin credentials (shell history sync)
    ATUIN_USERNAME=$(read_secret "op://DEV_CLI/Atuin/username")
    ATUIN_PASSWORD=$(read_secret "op://DEV_CLI/Atuin/password")
    ATUIN_KEY=$(read_secret "op://DEV_CLI/Atuin/key")
    if [[ -n "$ATUIN_USERNAME" ]]; then
        log "  - Atuin credentials loaded"
    fi

    # Pet GitHub token (snippet sync)
    PET_GITHUB_TOKEN=$(read_secret "op://DEV_CLI/Pet/PAT")
    if [[ -n "$PET_GITHUB_TOKEN" ]]; then
        log "  - Pet token loaded"
    fi

    # Tailscale auth key (tagged for devpod - receive only)
    # Use devpod_auth_key if available, fallback to regular auth_key
    TAILSCALE_AUTH_KEY=$(read_secret "op://DEV_CLI/Tailscale/devpod_auth_key")
    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        TAILSCALE_AUTH_KEY=$(read_secret "op://DEV_CLI/Tailscale/auth_key")
    fi
    TAILSCALE_API_KEY=$(read_secret "op://DEV_CLI/Tailscale/api_key")
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        log "  - Tailscale keys loaded"
    fi

    return 0
}

# Validate that required secrets are present
validate_secrets() {
    local missing=0

    if [[ -z "$GITHUB_TOKEN" ]]; then
        error "GITHUB_TOKEN not set"
        missing=1
    fi

    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        error "TAILSCALE_AUTH_KEY not set"
        missing=1
    fi

    return $missing
}

# Export secrets for devpod workspace
export_secrets_env() {
    # Export as environment variables
    export GITHUB_TOKEN
    export GH_TOKEN="$GITHUB_TOKEN"
    export ATUIN_USERNAME
    export ATUIN_PASSWORD
    export ATUIN_KEY
    export PET_GITHUB_TOKEN
    export TAILSCALE_AUTH_KEY
    export TAILSCALE_API_KEY
}
