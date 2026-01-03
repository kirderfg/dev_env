#!/bin/bash
# Common utilities for dev_env scripts
# Source this file in any script: source "$(dirname "${BASH_SOURCE[0]}")/../core/common.sh"

# Resolve script directory (works even when sourced)
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_ROOT="$(cd "$CORE_DIR/../.." && pwd)"

# Colors
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Script name for logging (set by sourcing script)
: "${SCRIPT_NAME:=$(basename "${BASH_SOURCE[-1]}")}"

# Logging functions
log() { echo -e "${GREEN}[${SCRIPT_NAME}]${NC} $1"; }
warn() { echo -e "${YELLOW}[${SCRIPT_NAME}]${NC} $1"; }
error() { echo -e "${RED}[${SCRIPT_NAME}]${NC} $1" >&2; }
info() { echo -e "${BLUE}[${SCRIPT_NAME}]${NC} $1"; }

# Check if command exists
require_cmd() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command not found: $1"
        return 1
    fi
}

# Check if file exists
require_file() {
    if [[ ! -f "$1" ]]; then
        error "Required file not found: $1"
        return 1
    fi
}

# Check if directory exists
require_dir() {
    if [[ ! -d "$1" ]]; then
        error "Required directory not found: $1"
        return 1
    fi
}

# Confirm action with user (default no)
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        read -p "$prompt [Y/n] " response
        [[ -z "$response" || "$response" =~ ^[Yy] ]]
    else
        read -p "$prompt [y/N] " response
        [[ "$response" =~ ^[Yy] ]]
    fi
}

# Extract workspace name from repo URL
get_workspace_name() {
    local repo="$1"
    # Extract last part of URL, remove .git suffix
    echo "$repo" | sed 's|.*/||' | sed 's|\.git$||'
}

# Check if running inside a devpod container
is_devpod() {
    [[ -f /.dockerenv ]] || [[ -n "$DEVPOD" ]]
}

# Check if running on the VM (not in container)
is_vm() {
    ! is_devpod
}
