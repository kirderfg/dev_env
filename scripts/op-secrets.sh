#!/bin/bash
# 1Password secrets loader - source this file to load secrets on-demand
# Secrets are fetched from 1Password and never touch disk
#
# Usage (in .zshrc or .bashrc):
#   source /path/to/op-secrets.sh
#
# Or load specific secrets:
#   eval "$(op-load-secret OPENAI_API_KEY 'op://DEV_CLI/OpenAI/api_key')"

OP_VAULT="${OP_VAULT:-DEV_CLI}"

# Check if 1Password CLI is available and authenticated
op-check() {
    if ! command -v op &>/dev/null; then
        echo "op CLI not installed" >&2
        return 1
    fi
    if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
        echo "OP_SERVICE_ACCOUNT_TOKEN not set" >&2
        return 1
    fi
    return 0
}

# Load a single secret: op-load-secret VAR_NAME "op://vault/item/field"
op-load-secret() {
    local var_name="$1"
    local secret_ref="$2"

    if ! op-check 2>/dev/null; then
        return 1
    fi

    local value
    value=$(op read "$secret_ref" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$value" ]; then
        export "$var_name"="$value"
        return 0
    fi
    return 1
}

# Load all configured secrets (call this from shell init)
op-load-all-secrets() {
    if ! op-check; then
        echo "[op-secrets] Skipping - 1Password not configured" >&2
        return 1
    fi

    local loaded=0
    local failed=0

    # Atuin credentials
    if op-load-secret ATUIN_KEY "op://${OP_VAULT}/Atuin/key"; then
        ((loaded++))
    else
        ((failed++))
    fi

    if op-load-secret ATUIN_PASSWORD "op://${OP_VAULT}/Atuin/password"; then
        ((loaded++))
    else
        ((failed++))
    fi

    if op-load-secret ATUIN_USERNAME "op://${OP_VAULT}/Atuin/username"; then
        ((loaded++))
    else
        ((failed++))
    fi

    # Pet snippets
    if op-load-secret PET_SNIPPETS_TOKEN "op://${OP_VAULT}/Pet/PAT"; then
        ((loaded++))
    else
        ((failed++))
    fi

    # OpenAI
    if op-load-secret OPENAI_API_KEY "op://${OP_VAULT}/OpenAI/api_key"; then
        ((loaded++))
    else
        ((failed++))
    fi

    # GitHub token (for gh CLI and git operations)
    if op-load-secret GITHUB_TOKEN "op://${OP_VAULT}/GitHub/PAT"; then
        ((loaded++))
    else
        ((failed++))
    fi

    echo "[op-secrets] Loaded ${loaded} secrets (${failed} not found/configured)" >&2
    return 0
}

# Auto-login to Atuin if credentials are available
op-atuin-login() {
    if ! command -v atuin &>/dev/null; then
        return 1
    fi

    # Check if already logged in
    if atuin status 2>/dev/null | grep -q "logged in"; then
        return 0
    fi

    if [ -n "$ATUIN_USERNAME" ] && [ -n "$ATUIN_PASSWORD" ] && [ -n "$ATUIN_KEY" ]; then
        atuin login -u "$ATUIN_USERNAME" -p "$ATUIN_PASSWORD" -k "$ATUIN_KEY" 2>/dev/null
        return $?
    fi
    return 1
}

# If sourced (not executed), auto-load secrets
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] || [[ -n "$ZSH_VERSION" ]]; then
    op-load-all-secrets
fi
