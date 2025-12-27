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
ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=accept-new \
    -L 3000:localhost:3000 \
    -L 5000:localhost:5000 \
    -L 5173:localhost:5173 \
    -L 8283:localhost:8283 \
    -L 5432:localhost:5432 \
    "${SSH_USER}@${VM_IP}"
