#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

echo "=== Dev Environment Setup ==="
echo ""

# Track what we need to do
NEED_DEVPOD=false
NEED_VM=false

# Check DevPod
if command -v devpod &> /dev/null; then
    echo "[OK] DevPod installed: $(devpod version 2>/dev/null | head -1)"
else
    echo "[--] DevPod not installed"
    NEED_DEVPOD=true
fi

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo ""
    echo "Error: Azure CLI is not installed."
    echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check Azure login
if ! az account show &> /dev/null; then
    echo ""
    echo "Error: Not logged in to Azure. Run 'az login' first."
    exit 1
fi

# Load env file if exists
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

# Install DevPod if needed
if [ "$NEED_DEVPOD" = true ]; then
    echo "Installing DevPod CLI..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  DEVPOD_ARCH="amd64" ;;
        aarch64) DEVPOD_ARCH="arm64" ;;
        arm64)   DEVPOD_ARCH="arm64" ;;
        *)
            echo "Error: Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    # Install to ~/.local/bin (no sudo required)
    mkdir -p "${HOME}/.local/bin"
    curl -L -o /tmp/devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-${DEVPOD_ARCH}"
    install -m 0755 /tmp/devpod "${HOME}/.local/bin/devpod"
    rm -f /tmp/devpod

    # Add to PATH if not already there
    if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
        export PATH="${HOME}/.local/bin:${PATH}"
        echo "Added ~/.local/bin to PATH for this session"
        echo ""
        echo "To make permanent, add to your shell profile:"
        echo "  echo 'export PATH=\"\${HOME}/.local/bin:\${PATH}\"' >> ~/.bashrc"
        echo ""
    fi

    echo "DevPod installed: $(devpod version 2>/dev/null | head -1)"
    echo ""
fi

# Deploy VM if needed
if [ "$NEED_VM" = true ]; then
    echo "Deploying VM..."
    "${SCRIPT_DIR}/scripts/deploy.sh"
    echo ""
fi

# Configure DevPod SSH provider
echo "Configuring DevPod..."
"${SCRIPT_DIR}/scripts/devpod-setup.sh"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You're ready to use DevPod with your dev VM!"
echo ""
echo "Try it out:"
echo "  devpod up github.com/microsoft/vscode-remote-try-go --provider ssh --option HOST=dev-vm --ide vscode"
echo ""
