#!/bin/bash
# Stop all devpod workspaces
# Usage: stop-all.sh

set -e

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="devpod-stop-all"
source "$SCRIPT_DIR/../core/common.sh"

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
