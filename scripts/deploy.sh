#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-dev-env"
LOCATION="swedencentral"
VM_NAME="vm-dev"
SSH_USER="azureuser"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"
ENV_FILE="${SCRIPT_DIR}/../.env"

echo "=== Azure Dev VM Deployment ==="
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed."
    echo "Run this from Azure Cloud Shell or install az CLI locally."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "Error: Not logged in to Azure. Run 'az login' first."
    exit 1
fi

# Check for Azure Cloud Shell and recommend persistent setup
if [ -n "$AZURE_HTTP_USER_AGENT" ] || [ -d ~/clouddrive ]; then
    # We're in Azure Cloud Shell
    PERSISTENT_BIN="$HOME/clouddrive/bin"
    PERSISTENT_NPM_PREFIX="$HOME/clouddrive/.npm-global"

    # Add persistent paths to PATH for this session
    export PATH="$PERSISTENT_BIN:$PERSISTENT_NPM_PREFIX/bin:$PATH"

    # Check if bootstrap has been run
    if [ ! -x "$PERSISTENT_BIN/op" ]; then
        echo ""
        echo "Azure Cloud Shell detected but persistent tools not installed."
        echo ""
        echo "For a better experience with persistent installations, run:"
        echo "  curl -fsSL https://raw.githubusercontent.com/kirderfg/dev_env/main/scripts/setup-cloudshell.sh | bash"
        echo "  source ~/.bashrc"
        echo ""
        echo "This installs tools to ~/clouddrive so they persist across sessions."
        echo ""
        read -p "Continue with temporary installation? (y/n): " -n 1 -r </dev/tty
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
fi

# Install 1Password CLI if not present
if ! command -v op &> /dev/null; then
    echo "Installing 1Password CLI..."
    # Use persistent location in Cloud Shell, otherwise ~/bin
    if [ -d ~/clouddrive ]; then
        INSTALL_BIN="$HOME/clouddrive/bin"
    else
        INSTALL_BIN="$HOME/bin"
    fi
    mkdir -p "$INSTALL_BIN"
    curl -sSfLo /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/v2.30.0/op_linux_amd64_v2.30.0.zip"
    unzip -o -q /tmp/op.zip -d /tmp/op_extracted
    mv /tmp/op_extracted/op "$INSTALL_BIN/op"
    chmod +x "$INSTALL_BIN/op"
    rm -rf /tmp/op.zip /tmp/op_extracted
    export PATH="$INSTALL_BIN:$PATH"
    echo "1Password CLI installed to $INSTALL_BIN/op"
fi

# Prompt for 1Password token
echo ""
echo "Enter your 1Password Service Account Token"
echo "(needed to fetch Tailscale auth key for VM setup)"
echo ""
read -s -r -p "Token: " OP_SERVICE_ACCOUNT_TOKEN
echo ""

if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    echo "Error: No token provided"
    exit 1
fi
export OP_SERVICE_ACCOUNT_TOKEN

# Verify token works
echo "Verifying 1Password token..."
if ! op whoami &>/dev/null; then
    echo "Error: 1Password authentication failed. Check your token."
    exit 1
fi
echo "1Password authenticated"

# Check if VM already exists
echo "Checking for existing VM..."
VM_EXISTS=$(az vm show --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" --query "id" -o tsv 2>/dev/null || true)

if [ -n "$VM_EXISTS" ]; then
    echo ""
    echo "WARNING: VM '${VM_NAME}' already exists in resource group '${RESOURCE_GROUP}'."
    echo "Cloud-init configuration cannot be changed on an existing VM."
    echo ""
    read -p "Delete resource group and start fresh? (y/n): " -n 1 -r REPLY </dev/tty
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting resource group ${RESOURCE_GROUP}..."
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait

        echo "Waiting for deletion to complete..."
        while az group show --name "${RESOURCE_GROUP}" &>/dev/null; do
            echo -n "."
            sleep 5
        done
        echo ""
        echo "Resource group deleted."
    else
        echo "Aborting. To update NSG rules only, use Azure Portal or az CLI directly."
        exit 0
    fi
fi

# Generate throwaway SSH key (required by Azure, but we use Tailscale for access)
echo "Generating temporary SSH key for Azure..."
TEMP_KEY=$(mktemp -u)  # -u creates name only, doesn't create file
ssh-keygen -t ed25519 -f "$TEMP_KEY" -N "" -q -C "azure-deploy-temp"
SSH_PUBLIC_KEY=$(cat "${TEMP_KEY}.pub")
rm -f "$TEMP_KEY" "${TEMP_KEY}.pub"
echo "SSH key generated (throwaway - access is via Tailscale)"

# Get Tailscale keys from 1Password
echo ""
echo "Fetching Tailscale keys from 1Password..."
TAILSCALE_AUTH_KEY=$(op read "op://DEV_CLI/Tailscale/auth_key" 2>/dev/null || true)
TAILSCALE_API_KEY=$(op read "op://DEV_CLI/Tailscale/api_key" 2>/dev/null || true)

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "Error: Tailscale auth key not found in 1Password (op://DEV_CLI/Tailscale/auth_key)"
    exit 1
fi
echo "Tailscale auth key found"

if [ -n "$TAILSCALE_API_KEY" ]; then
    echo "Tailscale API key found - old 'dev-vm' device will be removed"
fi

# Create resource group if it doesn't exist
echo "Creating resource group ${RESOURCE_GROUP}..."
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none

# Deploy infrastructure
echo "Deploying infrastructure..."
DEPLOY_PARAMS=(
    --resource-group "${RESOURCE_GROUP}"
    --template-file "${INFRA_DIR}/main.bicep"
    --parameters
        location="swedencentral"
        namePrefix="dev-env"
        vmName="${VM_NAME}"
        vmSize="Standard_D8s_v6"
        osDiskSizeGB=64
        sshPublicKey="${SSH_PUBLIC_KEY}"
)
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    DEPLOY_PARAMS+=(tailscaleAuthKey="${TAILSCALE_AUTH_KEY}")
fi
if [ -n "$TAILSCALE_API_KEY" ]; then
    DEPLOY_PARAMS+=(tailscaleApiKey="${TAILSCALE_API_KEY}")
fi
az deployment group create "${DEPLOY_PARAMS[@]}" --output table

# Get public IP (still assigned, but SSH blocked by NSG)
echo ""
echo "=== Deployment Complete ==="
PUBLIC_IP=$(az vm show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --show-details \
    --query publicIps \
    --output tsv | tr -d '\r')

# Write config to .env file
cat > "${ENV_FILE}" << EOF
# Dev VM Configuration
# Auto-generated by deploy.sh on $(date)

VM_NAME=${VM_NAME}
RESOURCE_GROUP=${RESOURCE_GROUP}
SSH_USER=${SSH_USER}
TAILSCALE_HOSTNAME=dev-vm
EOF

echo "Config saved to ${ENV_FILE}"
echo ""
echo "Public IP: ${PUBLIC_IP} (SSH blocked by NSG - use Tailscale)"

echo ""
echo "=== Waiting for cloud-init to complete ==="

# Wait for cloud-init using az vm run-command
echo "Checking cloud-init status..."
for i in {1..60}; do
    CLOUD_INIT_STATUS=$(az vm run-command invoke \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${VM_NAME}" \
        --command-id RunShellScript \
        --scripts "cloud-init status 2>/dev/null | grep -o 'done\|running\|error' || echo 'waiting'" \
        --query "value[0].message" -o tsv 2>/dev/null | grep -o 'done\|running\|error\|waiting' | head -1)

    if [ "$CLOUD_INIT_STATUS" = "done" ]; then
        echo ""
        echo "Cloud-init completed"
        break
    elif [ "$CLOUD_INIT_STATUS" = "error" ]; then
        echo ""
        echo "Cloud-init failed - check VM logs"
        break
    fi
    echo -n "."
    sleep 10
done
echo ""

echo ""
echo "=== VM Ready ==="
echo ""
echo "Next steps:"
echo ""
echo "1. SSH into the VM:"
echo "   ssh ${SSH_USER}@dev-vm"
echo ""
echo "2. Clone dev_env and run setup:"
echo "   git clone https://github.com/kirderfg/dev_env.git ~/dev_env"
echo "   ~/dev_env/scripts/setup-vm.sh"
echo ""
