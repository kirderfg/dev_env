#!/bin/bash
# Install and enable devpod autostart systemd service
# Run this script once to set up auto-start on reboot

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="$SCRIPT_DIR/devpod-autostart.service"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[setup-autostart]${NC} $1"; }
warn() { echo -e "${YELLOW}[setup-autostart]${NC} $1"; }

if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "Service file not found: $SERVICE_FILE"
    exit 1
fi

log "Installing devpod-autostart service..."
sudo cp "$SERVICE_FILE" /etc/systemd/system/devpod-autostart.service

log "Reloading systemd daemon..."
sudo systemctl daemon-reload

log "Enabling service to start on boot..."
sudo systemctl enable devpod-autostart.service

log "Starting service now..."
sudo systemctl start devpod-autostart.service || warn "Service may already be running"

log "Service status:"
sudo systemctl status devpod-autostart.service --no-pager || true

log "Done! DevPods will now auto-start on machine reboot."
log "Commands:"
log "  sudo systemctl status devpod-autostart  # Check status"
log "  sudo systemctl restart devpod-autostart # Restart all devpods"
log "  sudo systemctl disable devpod-autostart # Disable auto-start"
