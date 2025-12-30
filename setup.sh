#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
OP_TOKEN_FILE="${HOME}/.config/dev_env/op_token"

echo "=== Dev Environment Setup ==="
echo ""

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed."
    echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check Azure login
if ! az account show &> /dev/null; then
    echo "Error: Not logged in to Azure. Run 'az login' first."
    exit 1
fi

# Check for 1Password token (required for full automation)
if [ -f "$OP_TOKEN_FILE" ]; then
    echo "[OK] 1Password token found"
else
    echo "[--] 1Password token not found at $OP_TOKEN_FILE"
    echo "     GitHub auth and dev_env clone will need to be done manually on the VM"
fi

# Load env file if exists
NEED_VM=false
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
fi

# Check if VM exists
if [ -n "${VM_NAME}" ] && [ -n "${RESOURCE_GROUP}" ]; then
    VM_STATE=$(az vm show -g "${RESOURCE_GROUP}" -n "${VM_NAME}" --query "provisioningState" -o tsv 2>/dev/null | tr -d '\r' || echo "NotFound")
    if [ "${VM_STATE}" = "Succeeded" ]; then
        echo "[OK] VM exists: ${VM_NAME} (${VM_IP})"
    else
        echo "[--] VM not found or not ready"
        NEED_VM=true
    fi
else
    echo "[--] VM not deployed"
    NEED_VM=true
fi

echo ""

# Deploy VM if needed
if [ "$NEED_VM" = true ]; then
    echo "Deploying VM..."
    "${SCRIPT_DIR}/scripts/deploy.sh"
    echo ""
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Your dev VM is ready! DevPod and dev_env are installed on the VM."
echo ""
echo "Connect to the VM:"
echo "  ./scripts/ssh-connect.sh"
echo ""
echo "Then run devpods with:"
echo "  ~/dev_env/scripts/dp.sh up https://github.com/user/repo"
echo "  ~/dev_env/scripts/dp.sh list"
echo ""
