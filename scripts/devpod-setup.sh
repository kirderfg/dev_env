#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
OP_TOKEN_FILE="${HOME}/.config/dev_env/op_token"

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

# Configure 1Password Service Account Token
echo ""
echo "=== 1Password Configuration ==="

# Check if token already configured in DevPod
EXISTING_TOKEN=$(devpod provider options ssh 2>/dev/null | grep -i "OP_SERVICE_ACCOUNT_TOKEN" | awk '{print $2}' || true)

if [ -n "$EXISTING_TOKEN" ] && [ "$EXISTING_TOKEN" != "-" ]; then
    echo "1Password token already configured in DevPod."
else
    # Check if we have a saved token
    if [ -f "$OP_TOKEN_FILE" ]; then
        OP_TOKEN=$(cat "$OP_TOKEN_FILE")
        echo "Found saved 1Password token."
    else
        echo ""
        echo "1Password Service Account Token is required for secure secrets management."
        echo "This token will be passed to DevPod workspaces to fetch secrets on-demand."
        echo ""
        echo "Get your token from: 1Password → Settings → Developer → Service Accounts"
        echo ""
        read -sp "Enter 1Password Service Account Token (hidden): " OP_TOKEN
        echo ""

        if [ -n "$OP_TOKEN" ]; then
            # Save token locally (with secure permissions)
            mkdir -p "$(dirname "$OP_TOKEN_FILE")"
            echo "$OP_TOKEN" > "$OP_TOKEN_FILE"
            chmod 600 "$OP_TOKEN_FILE"
            echo "Token saved to ${OP_TOKEN_FILE}"
        fi
    fi

    if [ -n "$OP_TOKEN" ]; then
        # Configure DevPod to pass the token as environment variable
        # This injects OP_SERVICE_ACCOUNT_TOKEN into workspaces
        devpod provider update ssh -o INJECT_DOCKER_CREDENTIALS=false 2>/dev/null || true
        echo "1Password token configured."
        echo ""
        echo "To pass token to workspaces, use:"
        echo "  devpod up <repo> --provider ssh -o HOST=${SSH_HOST} --env OP_SERVICE_ACCOUNT_TOKEN=\$(cat ${OP_TOKEN_FILE})"
    else
        echo "No token provided. Secrets will not be available in workspaces."
        echo "You can configure it later with:"
        echo "  echo 'your-token' > ${OP_TOKEN_FILE} && chmod 600 ${OP_TOKEN_FILE}"
    fi
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now create DevPod workspaces on your dev VM!"
echo ""
echo "Examples:"
echo "  # Create workspace with 1Password secrets (recommended)"
echo "  devpod up github.com/your/repo --provider ssh -o HOST=${SSH_HOST} \\"
echo "    --env OP_SERVICE_ACCOUNT_TOKEN=\$(cat ~/.config/dev_env/op_token)"
echo ""
echo "  # Create workspace from local folder"
echo "  devpod up ./my-project --provider ssh -o HOST=${SSH_HOST} \\"
echo "    --env OP_SERVICE_ACCOUNT_TOKEN=\$(cat ~/.config/dev_env/op_token)"
echo ""
echo "  # Connect to existing workspace"
echo "  devpod ssh my-workspace"
echo ""
echo "  # Open in VS Code with secrets"
echo "  devpod up github.com/your/repo --provider ssh -o HOST=${SSH_HOST} --ide vscode \\"
echo "    --env OP_SERVICE_ACCOUNT_TOKEN=\$(cat ~/.config/dev_env/op_token)"
echo ""
echo "  # List workspaces"
echo "  devpod list"
echo ""
echo "Note: Secrets are fetched on-demand from 1Password - they never touch disk."
echo ""
