#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="start-vm"
source "$SCRIPT_DIR/../core/common.sh"

ENV_FILE="${SCRIPT_DIR}/../../.env"

# Load config
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
else
    error "Config file not found at ${ENV_FILE}"
    error "Run scripts/azure/deploy.sh first."
    exit 1
fi

log "Starting VM ${VM_NAME}..."
az vm start \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --output none

log "VM started. Getting public IP..."
NEW_IP=$(az vm show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --show-details \
    --query publicIps \
    --output tsv | tr -d '\r')

# Update .env if IP changed
if [ "${NEW_IP}" != "${VM_IP}" ]; then
    sed -i "s/^VM_IP=.*/VM_IP=${NEW_IP}/" "${ENV_FILE}"
    info "IP changed: ${VM_IP} -> ${NEW_IP}"
    info "Updated ${ENV_FILE}"
fi

echo ""
log "VM is running at: ${NEW_IP}"
info "Connect with: ssh azureuser@dev-vm (via Tailscale)"
