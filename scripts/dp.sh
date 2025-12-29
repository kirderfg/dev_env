#!/bin/bash
# dp - DevPod wrapper with 1Password token injection
# Usage: dp up <repo> [options]
#        dp ssh <workspace>
#        dp delete <workspace>
#        dp list
#        dp <any devpod command>

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[devpod]${NC} $1"; }
warn() { echo -e "${YELLOW}[devpod]${NC} $1"; }
error() { echo -e "${RED}[devpod]${NC} $1" >&2; }

OP_TOKEN_FILE="${HOME}/.config/dev_env/op_token"

# Load 1Password token
load_op_token() {
    if [[ -f "$OP_TOKEN_FILE" ]]; then
        OP_TOKEN=$(cat "$OP_TOKEN_FILE")
        if [[ -n "$OP_TOKEN" ]]; then
            return 0
        fi
    fi
    warn "1Password token not found at $OP_TOKEN_FILE"
    warn "Secrets won't be available in devcontainer"
    return 1
}

# Show usage
usage() {
    cat <<EOF
DevPod wrapper with automatic 1Password token injection

Usage: $(basename "$0") <command> [options]

Commands:
  up <repo>       Create/start workspace (injects OP token automatically)
  ssh <workspace> SSH into workspace
  delete <ws>     Delete workspace
  list            List workspaces
  rebuild <ws>    Rebuild workspace (recreate with OP token)
  *               Pass-through to devpod

Examples:
  $(basename "$0") up github.com/user/repo
  $(basename "$0") up github.com/user/repo --ide vscode
  $(basename "$0") rebuild myworkspace
  $(basename "$0") ssh myworkspace
  $(basename "$0") list

The script automatically:
- Injects OP_SERVICE_ACCOUNT_TOKEN from ~/.config/dev_env/op_token
- Sets SHELL_BOOTSTRAP_NONINTERACTIVE=1 for container setup
- Uses the 'ssh' provider with HOST=dev-vm by default

EOF
    exit 0
}

# Main logic
main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        up)
            if [[ $# -eq 0 ]]; then
                error "Usage: $(basename "$0") up <repo> [options]"
                exit 1
            fi

            local repo="$1"
            shift

            # Build devpod command with token injection
            local devpod_args=(
                "up" "$repo"
                "--provider" "ssh"
                "--provider-option" "HOST=dev-vm"
            )

            # Add workspace-env for 1Password token
            if load_op_token; then
                devpod_args+=("--workspace-env" "OP_SERVICE_ACCOUNT_TOKEN=$OP_TOKEN")
                log "1Password token will be injected"
            fi

            # Add non-interactive flag for shell-bootstrap
            devpod_args+=("--workspace-env" "SHELL_BOOTSTRAP_NONINTERACTIVE=1")

            # Add any additional arguments passed by user
            devpod_args+=("$@")

            log "Creating workspace for $repo..."
            devpod "${devpod_args[@]}"
            ;;

        rebuild)
            if [[ $# -eq 0 ]]; then
                error "Usage: $(basename "$0") rebuild <workspace>"
                exit 1
            fi

            local workspace="$1"
            shift

            # Build devpod command with recreate flag
            local devpod_args=(
                "up" "$workspace"
                "--provider" "ssh"
                "--provider-option" "HOST=dev-vm"
                "--recreate"
            )

            # Add workspace-env for 1Password token
            if load_op_token; then
                devpod_args+=("--workspace-env" "OP_SERVICE_ACCOUNT_TOKEN=$OP_TOKEN")
                log "1Password token will be injected"
            fi

            devpod_args+=("--workspace-env" "SHELL_BOOTSTRAP_NONINTERACTIVE=1")
            devpod_args+=("$@")

            log "Rebuilding workspace $workspace..."
            devpod "${devpod_args[@]}"
            ;;

        ssh|delete|list|status|stop|logs)
            # Pass-through commands
            devpod "$cmd" "$@"
            ;;

        *)
            # Unknown command - pass through to devpod
            devpod "$cmd" "$@"
            ;;
    esac
}

main "$@"
