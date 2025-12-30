#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

echo ""

# Always run deploy (it handles existing VM check with y/n prompt)
"${SCRIPT_DIR}/scripts/deploy.sh"

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
