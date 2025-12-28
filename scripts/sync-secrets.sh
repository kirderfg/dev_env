#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
LOCAL_SECRETS="${HOME}/.config/shell-bootstrap/secrets.env"

# Load VM config
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
else
    echo "Error: Config file not found. Run ./scripts/deploy.sh first."
    exit 1
fi

SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

echo "=== Syncing secrets to VM ==="

# Build secrets content
SECRETS_CONTENT="# Shell Bootstrap Secrets - synced from local machine
# Generated on $(date)
"

# Get Atuin key if available
if command -v atuin &>/dev/null; then
    ATUIN_KEY=$(atuin key 2>/dev/null || true)
    if [ -n "$ATUIN_KEY" ]; then
        echo "Found Atuin key"
        SECRETS_CONTENT+="
export ATUIN_KEY=\"${ATUIN_KEY}\""
    fi
fi

# Get Atuin password from local secrets if exists
if [ -f "$LOCAL_SECRETS" ]; then
    ATUIN_PASSWORD=$(grep -oP 'export ATUIN_PASSWORD="\K[^"]+' "$LOCAL_SECRETS" 2>/dev/null || true)
    if [ -n "$ATUIN_PASSWORD" ]; then
        echo "Found Atuin password"
        SECRETS_CONTENT+="
export ATUIN_PASSWORD=\"${ATUIN_PASSWORD}\""
    fi

    PET_TOKEN=$(grep -oP 'export PET_SNIPPETS_TOKEN="\K[^"]+' "$LOCAL_SECRETS" 2>/dev/null || true)
    if [ -n "$PET_TOKEN" ]; then
        echo "Found Pet snippets token"
        SECRETS_CONTENT+="
export PET_SNIPPETS_TOKEN=\"${PET_TOKEN}\""
    fi
fi

# Create temp file and copy to VM
TEMP_SECRETS=$(mktemp)
echo "$SECRETS_CONTENT" > "$TEMP_SECRETS"

echo "Copying secrets to VM..."
ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${VM_IP}" \
    "mkdir -p ~/.config/shell-bootstrap && chmod 700 ~/.config/shell-bootstrap"

scp -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=accept-new \
    "$TEMP_SECRETS" "${SSH_USER}@${VM_IP}:~/.config/shell-bootstrap/secrets.env"

ssh -i "${SSH_KEY_PATH}" "${SSH_USER}@${VM_IP}" \
    "chmod 600 ~/.config/shell-bootstrap/secrets.env"

rm -f "$TEMP_SECRETS"

echo ""
echo "Secrets synced! On the VM, run:"
echo "  source ~/.config/shell-bootstrap/secrets.env"
echo "  atuin login -u <username> -p \"\$ATUIN_PASSWORD\" -k \"\$ATUIN_KEY\""
echo "  atuin sync"
