#!/bin/bash
# Stop all devpod workspaces
# Usage: devpod-stop-all.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[devpod-stop-all]${NC} $1"; }
warn() { echo -e "${YELLOW}[devpod-stop-all]${NC} $1"; }
error() { echo -e "${RED}[devpod-stop-all]${NC} $1" >&2; }

# Get list of all workspaces
get_workspaces() {
    devpod list --output json 2>/dev/null | jq -r '.[].id' 2>/dev/null || true
}

main() {
    log "Fetching workspace list..."
    local workspaces
    workspaces=$(get_workspaces)

    if [[ -z "$workspaces" ]]; then
        warn "No workspaces found"
        exit 0
    fi

    log "Found workspaces: $(echo "$workspaces" | tr '\n' ' ')"

    for ws in $workspaces; do
        log "Stopping workspace: $ws"
        devpod stop "$ws" 2>&1 || warn "Failed to stop $ws"
    done

    log "All workspaces stopped"
}

main "$@"
