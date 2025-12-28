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
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"

echo "=== Syncing secrets to VM ==="

# Source local secrets if available
if [ -f "$LOCAL_SECRETS" ]; then
    source "$LOCAL_SECRETS"
fi

# Build secrets content
SECRETS_CONTENT="# Shell Bootstrap Secrets - synced from local machine
# Generated on $(date)
"

HAVE_ATUIN=false

# Get Atuin key from command (most reliable)
if command -v atuin &>/dev/null; then
    ATUIN_KEY_CMD=$(atuin key 2>/dev/null || true)
    if [ -n "$ATUIN_KEY_CMD" ]; then
        ATUIN_KEY="$ATUIN_KEY_CMD"
    fi
fi

# Get Atuin username from config
if [ -f "${HOME}/.config/atuin/config.toml" ]; then
    ATUIN_USERNAME_CFG=$(grep -oP '^username\s*=\s*"\K[^"]+' "${HOME}/.config/atuin/config.toml" 2>/dev/null || true)
    if [ -n "$ATUIN_USERNAME_CFG" ]; then
        ATUIN_USERNAME="$ATUIN_USERNAME_CFG"
    fi
fi

# Check what we have for Atuin
if [ -n "$ATUIN_KEY" ] && [ -n "$ATUIN_PASSWORD" ] && [ -n "$ATUIN_USERNAME" ]; then
    echo "Found Atuin credentials (username: $ATUIN_USERNAME)"
    HAVE_ATUIN=true
    SECRETS_CONTENT+="
export ATUIN_USERNAME=\"${ATUIN_USERNAME}\"
export ATUIN_KEY=\"${ATUIN_KEY}\"
export ATUIN_PASSWORD=\"${ATUIN_PASSWORD}\""
elif [ -n "$ATUIN_KEY" ]; then
    echo "Found Atuin key (missing password or username - add to ~/.config/shell-bootstrap/secrets.env)"
    SECRETS_CONTENT+="
export ATUIN_KEY=\"${ATUIN_KEY}\""
fi

# Pet snippets token
if [ -n "$PET_SNIPPETS_TOKEN" ]; then
    echo "Found Pet snippets token"
    SECRETS_CONTENT+="
export PET_SNIPPETS_TOKEN=\"${PET_SNIPPETS_TOKEN}\""
fi

# Create temp file and copy to VM
TEMP_SECRETS=$(mktemp)
echo "$SECRETS_CONTENT" > "$TEMP_SECRETS"

echo "Copying secrets to VM..."
ssh -i "${SSH_KEY_PATH}" $SSH_OPTS "${SSH_USER}@${VM_IP}" \
    "mkdir -p ~/.config/shell-bootstrap && chmod 700 ~/.config/shell-bootstrap"

scp -i "${SSH_KEY_PATH}" $SSH_OPTS \
    "$TEMP_SECRETS" "${SSH_USER}@${VM_IP}:~/.config/shell-bootstrap/secrets.env"

ssh -i "${SSH_KEY_PATH}" $SSH_OPTS "${SSH_USER}@${VM_IP}" \
    "chmod 600 ~/.config/shell-bootstrap/secrets.env"

rm -f "$TEMP_SECRETS"

# Auto-login to Atuin on VM if we have full credentials
if [ "$HAVE_ATUIN" = true ]; then
    echo "Logging into Atuin on VM..."
    ssh -i "${SSH_KEY_PATH}" $SSH_OPTS "${SSH_USER}@${VM_IP}" bash -s <<EOF
source ~/.config/shell-bootstrap/secrets.env
export PATH="\$HOME/.atuin/bin:\$PATH"
if command -v atuin &>/dev/null; then
    atuin login -u "\$ATUIN_USERNAME" -p "\$ATUIN_PASSWORD" -k "\$ATUIN_KEY" 2>/dev/null && echo "Atuin login successful" || echo "Atuin login failed (may need to wait for cloud-init)"
    atuin sync 2>/dev/null || true
fi
EOF
fi

echo ""
echo "Secrets synced!"
