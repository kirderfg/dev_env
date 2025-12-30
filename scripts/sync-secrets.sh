#!/bin/bash
# Sync 1Password service account token to VM using az vm run-command
# Then re-runs shell-bootstrap to configure gh/atuin
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
LOCAL_TOKEN_FILE="${HOME}/.config/dev_env/op_token"

# Load VM config
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
fi

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dev-env}"
VM_NAME="${VM_NAME:-vm-dev}"
SSH_USER="${SSH_USER:-azureuser}"

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

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed"
    exit 1
fi

echo "Copying token to VM via az run-command..."

# Use az vm run-command to write token
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts "
mkdir -p /home/${SSH_USER}/.config/dev_env
chmod 700 /home/${SSH_USER}/.config/dev_env
cat > /home/${SSH_USER}/.config/dev_env/op_token << 'TOKENEOF'
${TOKEN}
TOKENEOF
chmod 600 /home/${SSH_USER}/.config/dev_env/op_token
chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.config/dev_env
echo 'Token written successfully'
" --query "value[0].message" -o tsv 2>/dev/null | tail -3

echo "✓ 1Password token synced"

# Verify and configure shell-bootstrap
echo ""
echo "=== Configuring gh/atuin via shell-bootstrap ==="
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts '
export OP_SERVICE_ACCOUNT_TOKEN="$(cat /home/'"${SSH_USER}"'/.config/dev_env/op_token 2>/dev/null)"

# Verify 1Password works
if op whoami &>/dev/null; then
    echo "✓ 1Password CLI authenticated"
else
    echo "✗ 1Password authentication failed"
    exit 1
fi

# Re-run shell-bootstrap to configure gh/atuin/git/pet
su - '"${SSH_USER}"' -c "
export OP_SERVICE_ACCOUNT_TOKEN=\"\$(cat ~/.config/dev_env/op_token)\"
curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/shell-bootstrap-install.sh
SHELL_BOOTSTRAP_NONINTERACTIVE=1 bash /tmp/shell-bootstrap-install.sh
rm -f /tmp/shell-bootstrap-install.sh
"
echo "✓ Shell environment configured"
' --query "value[0].message" -o tsv 2>/dev/null | tail -10

echo ""
echo "=== Sync Complete ==="
echo ""
echo "Token synced and shell configured. Connect with: ssh ${SSH_USER}@dev-vm"
echo ""
