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

# Expand ~ in SSH_KEY_PATH
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

# Check if SSH key exists
if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo "Error: SSH key not found at ${SSH_KEY_PATH}"
    echo "Run ./scripts/deploy.sh first."
    exit 1
fi

echo "Connecting to ${VM_IP}..."
ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${VM_IP}"
