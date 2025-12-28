#!/bin/bash
# Sync 1Password service account token to VM
# shell-bootstrap on VM will use this token on next shell start
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
LOCAL_TOKEN_FILE="${HOME}/.config/dev_env/op_token"

# Load VM config
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
else
    echo "Error: Config file not found. Run ./scripts/deploy.sh first."
    exit 1
fi

SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"

echo "=== Syncing 1Password Token to VM ==="

# Check for local token
if [ ! -f "$LOCAL_TOKEN_FILE" ]; then
    echo ""
    echo "1Password Service Account Token not found locally."
    echo ""
    echo "Run shell-bootstrap locally first to set up 1Password:"
    echo "  curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/install.sh"
    echo "  bash /tmp/install.sh"
    echo ""
    echo "Or manually save your token:"
    echo "  mkdir -p ~/.config/dev_env"
    echo "  echo 'your-token' > ~/.config/dev_env/op_token"
    echo "  chmod 600 ~/.config/dev_env/op_token"
    exit 1
fi

TOKEN=$(cat "$LOCAL_TOKEN_FILE")
if [ -z "$TOKEN" ]; then
    echo "Error: Token file exists but is empty"
    exit 1
fi

echo "Copying token to VM..."

# Create remote directory and copy token
ssh -i "${SSH_KEY_PATH}" $SSH_OPTS "${SSH_USER}@${VM_IP}" \
    "mkdir -p ~/.config/dev_env && chmod 700 ~/.config/dev_env"

# Copy token securely (never in shell history)
ssh -i "${SSH_KEY_PATH}" $SSH_OPTS "${SSH_USER}@${VM_IP}" bash -s <<EOF
cat > ~/.config/dev_env/op_token << 'TOKENEOF'
${TOKEN}
TOKENEOF
chmod 600 ~/.config/dev_env/op_token
EOF

# Verify op works on VM
echo ""
echo "Verifying 1Password on VM..."
ssh -i "${SSH_KEY_PATH}" $SSH_OPTS "${SSH_USER}@${VM_IP}" bash -s <<'EOF'
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/dev_env/op_token 2>/dev/null)"
if command -v op &>/dev/null; then
    if op whoami &>/dev/null; then
        echo "✓ 1Password CLI authenticated successfully"
    else
        echo "✗ 1Password authentication failed - check your token"
    fi
else
    echo "✗ 1Password CLI not installed"
    echo "  Run: sudo apt-get update && sudo apt-get install -y 1password-cli"
fi
EOF

echo ""
echo "=== Sync Complete ==="
echo ""
echo "Token synced to VM. Secrets will be loaded on next shell start."
echo "SSH to VM and start a new zsh session to load secrets."
echo ""
