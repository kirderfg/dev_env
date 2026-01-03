#!/bin/bash
# Start all devpod workspaces
# Usage: start-all.sh [--wait]

set -e

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="devpod-start-all"
source "$SCRIPT_DIR/../core/common.sh"

DP_SCRIPT="$SCRIPT_DIR/dp.sh"

# Get list of all workspaces
get_workspaces() {
    devpod list --output json 2>/dev/null | jq -r '.[].id' 2>/dev/null || true
}

# Start a single workspace
start_workspace() {
    local ws="$1"
    log "Starting workspace: $ws"
    "$DP_SCRIPT" up "$ws" 2>&1 | while read -r line; do
        echo "  [$ws] $line"
    done
}

main() {
    local wait_mode=false
    [[ "$1" == "--wait" ]] && wait_mode=true

    log "Fetching workspace list..."
    local workspaces
    workspaces=$(get_workspaces)

    if [[ -z "$workspaces" ]]; then
        warn "No workspaces found"
        exit 0
    fi

    log "Found workspaces: $(echo "$workspaces" | tr '\n' ' ')"

    # Start all workspaces in parallel
    local pids=()
    for ws in $workspaces; do
        start_workspace "$ws" &
        pids+=($!)
    done

    # Wait for all to complete
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed++))
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log "All workspaces started successfully"
    else
        error "$failed workspace(s) failed to start"
        exit 1
    fi
}

main "$@"
