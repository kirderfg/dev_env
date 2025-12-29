#!/bin/bash
# Setup Tailscale on dev VM using auth key from 1Password
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../.env" 2>/dev/null || true

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[Tailscale]${NC} $1"; }
warn() { echo -e "${YELLOW}[Tailscale]${NC} $1"; }
error() { echo -e "${RED}[Tailscale]${NC} $1" >&2; }

# Load 1Password token
if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ] && [ -f ~/.config/dev_env/op_token ]; then
    export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/dev_env/op_token)"
fi

if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    error "1Password token not found. Run sync-secrets.sh first."
    exit 1
fi

# Get Tailscale auth key from 1Password
log "Getting Tailscale auth key from 1Password..."
TAILSCALE_AUTH_KEY=$(op read "op://DEV_CLI/Tailscale/auth_key" 2>/dev/null)

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    error "Failed to get Tailscale auth key from 1Password"
    error "Ensure 'Tailscale' item exists in DEV_CLI vault with 'auth_key' field"
    exit 1
fi

# Determine target (local or remote VM)
if [ -n "$1" ]; then
    TARGET="$1"
elif [ -n "$VM_IP" ]; then
    TARGET="$VM_IP"
else
    error "No target specified. Usage: $0 [vm-ip|local]"
    error "Or set VM_IP in .env file"
    exit 1
fi

if [ "$TARGET" = "local" ]; then
    # Configure locally (for testing in containers)
    log "Configuring Tailscale locally..."

    if ! command -v tailscale &> /dev/null; then
        error "Tailscale not installed locally"
        exit 1
    fi

    # Check if already connected
    if tailscale status &> /dev/null; then
        CURRENT_STATUS=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.Online // false')
        if [ "$CURRENT_STATUS" = "true" ]; then
            log "Tailscale already connected"
            tailscale status --self
            exit 0
        fi
    fi

    log "Authenticating with Tailscale..."
    sudo tailscale up --authkey="$TAILSCALE_AUTH_KEY" --ssh
    log "Tailscale connected!"
    tailscale status --self
else
    # Configure on remote VM
    SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/dev_env_key}"
    SSH_USER="${SSH_USER:-azureuser}"

    log "Configuring Tailscale on $TARGET..."

    # Check if tailscale is installed
    if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$TARGET" "command -v tailscale" &> /dev/null; then
        error "Tailscale not installed on VM. Redeploy the VM to install it."
        exit 1
    fi

    # Check current status
    REMOTE_STATUS=$(ssh -i "$SSH_KEY" "$SSH_USER@$TARGET" "sudo tailscale status --self --json 2>/dev/null | jq -r '.Self.Online // false'" 2>/dev/null || echo "false")

    if [ "$REMOTE_STATUS" = "true" ]; then
        log "Tailscale already connected on VM"
        ssh -i "$SSH_KEY" "$SSH_USER@$TARGET" "tailscale status --self"

        # Show Tailscale IP
        TS_IP=$(ssh -i "$SSH_KEY" "$SSH_USER@$TARGET" "tailscale ip -4" 2>/dev/null)
        log "Tailscale IP: $TS_IP"
        log "You can now SSH via: ssh $SSH_USER@$TS_IP"
        exit 0
    fi

    log "Authenticating VM with Tailscale..."
    ssh -i "$SSH_KEY" "$SSH_USER@$TARGET" "sudo tailscale up --authkey='$TAILSCALE_AUTH_KEY' --ssh --hostname=dev-vm"

    log "Tailscale connected!"
    ssh -i "$SSH_KEY" "$SSH_USER@$TARGET" "tailscale status --self"

    # Show Tailscale IP
    TS_IP=$(ssh -i "$SSH_KEY" "$SSH_USER@$TARGET" "tailscale ip -4" 2>/dev/null)
    log "Tailscale IP: $TS_IP"
    log ""
    log "You can now SSH via Tailscale: ssh $SSH_USER@$TS_IP"
    log "Or use hostname: ssh $SSH_USER@dev-vm"
fi
