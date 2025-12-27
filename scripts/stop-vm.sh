#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

# Load config
if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
else
    echo "Error: Config file not found at ${ENV_FILE}"
    echo "Run ./scripts/deploy.sh first."
    exit 1
fi

echo "Stopping and deallocating VM ${VM_NAME}..."
echo "This will stop billing for compute (disk storage still charged)."

az vm deallocate \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --output none

echo "VM deallocated. Run ./scripts/start-vm.sh to start it again."
