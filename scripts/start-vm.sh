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

echo "Starting VM ${VM_NAME}..."
az vm start \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --output none

echo "VM started. Getting public IP..."
NEW_IP=$(az vm show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --show-details \
    --query publicIps \
    --output tsv)

# Update .env if IP changed
if [ "${NEW_IP}" != "${VM_IP}" ]; then
    sed -i "s/^VM_IP=.*/VM_IP=${NEW_IP}/" "${ENV_FILE}"
    echo "IP changed: ${VM_IP} -> ${NEW_IP}"
    echo "Updated ${ENV_FILE}"
fi

echo ""
echo "VM is running at: ${NEW_IP}"
echo "Connect with: ./scripts/ssh-connect.sh"
