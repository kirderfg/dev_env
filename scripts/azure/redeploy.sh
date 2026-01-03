#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="redeploy-vm"
source "$SCRIPT_DIR/../core/common.sh"

ENV_FILE="${SCRIPT_DIR}/../../.env"

log "=== VM Redeploy ==="
warn "This will DELETE the current VM and create a fresh one."
echo ""

# Load config
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
else
    info "No existing VM config found. Running fresh deploy..."
    exec "${SCRIPT_DIR}/deploy.sh"
fi

# Confirm
if ! confirm "Delete VM '${VM_NAME}' and redeploy?"; then
    log "Cancelled."
    exit 0
fi

# Delete VM (this also deletes NIC, disk, public IP due to deleteOption settings)
log "Deleting VM ${VM_NAME}..."
az vm delete \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --yes \
    --force-deletion true \
    --output none 2>/dev/null || true

# Wait a moment for cleanup
log "Waiting for cleanup..."
sleep 5

# Deploy fresh
echo ""
log "Deploying fresh VM..."
exec "${SCRIPT_DIR}/deploy.sh"
