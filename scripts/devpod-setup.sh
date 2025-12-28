#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

echo "=== DevPod SSH Provider Setup ==="

# Check if DevPod is installed
if ! command -v devpod &> /dev/null; then
    echo "Error: DevPod is not installed."
    echo ""
    echo "Run ./setup.sh to install automatically, or install manually:"
    echo ""
    echo "  # Linux (amd64)"
    echo "  curl -L -o devpod https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
    echo "  sudo install -c -m 0755 devpod /usr/local/bin && rm devpod"
    echo ""
    echo "  # macOS"
    echo "  brew install devpod"
    echo ""
    echo "  # Windows"
    echo "  winget install DevPod"
    echo ""
    echo "More info: https://devpod.sh/docs/getting-started/install"
    exit 1
fi

# Load VM config
if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: No VM configuration found at ${ENV_FILE}"
    echo "Run ./scripts/deploy.sh first to create the VM."
    exit 1
fi

source "${ENV_FILE}"

if [ -z "${VM_IP}" ]; then
    echo "Error: VM_IP not found in ${ENV_FILE}"
    exit 1
fi

echo "VM IP: ${VM_IP}"
echo "SSH Key: ${SSH_KEY_PATH}"
echo ""

# Add SSH config entry for the dev VM
SSH_CONFIG="${HOME}/.ssh/config"
SSH_HOST="dev-vm"

echo "Configuring SSH host '${SSH_HOST}'..."

# Remove existing entry if present
if grep -q "^Host ${SSH_HOST}$" "${SSH_CONFIG}" 2>/dev/null; then
    echo "Updating existing SSH config entry..."
    # Use sed to remove the existing block
    sed -i.bak "/^Host ${SSH_HOST}$/,/^Host /{ /^Host ${SSH_HOST}$/d; /^Host /!d; }" "${SSH_CONFIG}"
    # Clean up any remaining orphaned lines
    sed -i.bak "/^Host ${SSH_HOST}$/,/^$/d" "${SSH_CONFIG}"
fi

# Add new SSH config entry
cat >> "${SSH_CONFIG}" << EOF

# Dev VM for DevPod (auto-generated)
Host ${SSH_HOST}
    HostName ${VM_IP}
    User ${SSH_USER}
    IdentityFile ${SSH_KEY_PATH}
    StrictHostKeyChecking accept-new
EOF

echo "SSH config updated: ~/.ssh/config"

# Add SSH provider to DevPod
echo ""
echo "Adding SSH provider to DevPod..."
# Check if already installed, add if not (suppress interactive prompts)
if ! devpod provider list 2>/dev/null | grep -q "ssh"; then
    devpod provider add ssh --silent 2>/dev/null || devpod provider add ssh -o HOST=dev-vm 2>/dev/null || true
fi
echo "SSH provider ready."

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now create DevPod workspaces on your dev VM!"
echo ""
echo "Examples:"
echo "  # Create workspace from GitHub repo"
echo "  devpod up github.com/your/repo --provider ssh --option HOST=${SSH_HOST}"
echo ""
echo "  # Create workspace from local folder"
echo "  devpod up ./my-project --provider ssh --option HOST=${SSH_HOST}"
echo ""
echo "  # Connect to existing workspace"
echo "  devpod ssh my-workspace"
echo ""
echo "  # Open in VS Code"
echo "  devpod up github.com/your/repo --provider ssh --option HOST=${SSH_HOST} --ide vscode"
echo ""
echo "  # List workspaces"
echo "  devpod list"
echo ""
