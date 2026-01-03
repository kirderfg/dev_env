#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="stop-vm"
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

log "Stopping and deallocating VM ${VM_NAME}..."
info "This will stop billing for compute (disk storage still charged)."

az vm deallocate \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --output none

log "VM deallocated."
info "Run scripts/azure/start.sh to start it again."
