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
WORKSPACE_DIR="${HOME}/.devpod-workspaces"

# Update submodules to latest in a repo
update_submodules() {
    local repo_path="$1"
    if [[ -f "$repo_path/.gitmodules" ]]; then
        log "Updating submodules to latest..."
        (cd "$repo_path" && git submodule update --init --remote --merge 2>/dev/null) || warn "Submodule update failed (non-fatal)"
    fi
}

# Clone repo and update submodules, return local path
prepare_repo() {
    local repo="$1"

    # If it's already a local path, just update submodules in place
    if [[ -d "$repo" ]]; then
        update_submodules "$repo"
        echo "$repo"
        return 0
    fi

    # For URLs, clone to workspace dir and update submodules
    if [[ "$repo" =~ ^(https?://|git@|github\.com) ]]; then
        # Normalize github.com/user/repo to full URL
        if [[ "$repo" =~ ^github\.com ]]; then
            repo="https://$repo"
        fi

        # Extract workspace name from repo URL
        local ws_name=$(basename "$repo" .git)
        local local_path="$WORKSPACE_DIR/$ws_name"

        mkdir -p "$WORKSPACE_DIR"

        if [[ -d "$local_path" ]]; then
            log "Updating existing clone at $local_path..."
            (cd "$local_path" && git fetch origin && git reset --hard origin/main 2>/dev/null || git reset --hard origin/master) || true
        else
            log "Cloning $repo to $local_path..."
            git clone --recursive "$repo" "$local_path"
        fi

        update_submodules "$local_path"
        echo "$local_path"
        return 0
    fi

    # Unknown format, return as-is
    echo "$repo"
}

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
- Clones repos to ~/.devpod-workspaces/ and updates submodules to latest
- Injects OP_SERVICE_ACCOUNT_TOKEN from ~/.config/dev_env/op_token
- Sets SHELL_BOOTSTRAP_NONINTERACTIVE=1 for container setup
- Uses the 'docker' provider (local Docker on this VM)

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

            # Prepare repo (clone if URL, update submodules to latest)
            local local_path
            local_path=$(prepare_repo "$repo")

            # Build devpod command with token injection
            local devpod_args=(
                "up" "$local_path"
                "--provider" "docker"
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

            # For rebuild, update submodules in the workspace dir if it exists
            local ws_path="$WORKSPACE_DIR/$workspace"
            if [[ -d "$ws_path" ]]; then
                log "Pulling latest changes..."
                (cd "$ws_path" && git fetch origin && git reset --hard origin/main 2>/dev/null || git reset --hard origin/master) || true
                update_submodules "$ws_path"
            fi

            # Build devpod command with recreate flag
            local devpod_args=(
                "up" "$workspace"
                "--provider" "docker"
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
