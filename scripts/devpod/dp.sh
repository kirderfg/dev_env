#!/bin/bash
# dp - DevPod wrapper with secret injection (1Password stays on VM only)
# Secrets are read from 1Password on the VM and passed to containers as env vars
# Containers do NOT have access to 1Password CLI or tokens

set -e

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="devpod"
source "$SCRIPT_DIR/../core/common.sh"
source "$SCRIPT_DIR/../core/secrets.sh"

# Copy Claude credentials to devpod after it's created
copy_claude_credentials() {
    local workspace="$1"
    local claude_creds="$HOME/.claude/.credentials.json"

    if [[ ! -f "$claude_creds" ]]; then
        warn "Claude credentials not found at $claude_creds - skipping"
        return 0
    fi

    log "Copying Claude credentials to devpod..."

    # Base64 encode to avoid special character issues with devpod ssh
    local creds_b64
    creds_b64=$(base64 -w0 "$claude_creds")

    # Create .claude directory and decode credentials
    if devpod ssh "$workspace" -- "mkdir -p ~/.claude && chmod 700 ~/.claude && echo '$creds_b64' | base64 -d > ~/.claude/.credentials.json && chmod 600 ~/.claude/.credentials.json" 2>/dev/null; then
        log "Claude credentials copied successfully"
    else
        warn "Failed to copy Claude credentials"
    fi
}

# Show usage
usage() {
    cat <<EOF
DevPod wrapper with automatic secret injection (1Password stays on VM only)

Usage: $(basename "$0") <command> [options]

Commands:
  up <repo>       Create/start workspace (injects secrets from 1Password)
  ssh <workspace> SSH into workspace
  delete <ws>     Delete workspace
  list            List workspaces
  rebuild <ws>    Rebuild workspace (recreate with secrets)
  *               Pass-through to devpod

Examples:
  $(basename "$0") up github.com/user/repo
  $(basename "$0") up github.com/user/repo --ide vscode
  $(basename "$0") rebuild myworkspace
  $(basename "$0") ssh myworkspace
  $(basename "$0") list

The script automatically:
- Reads secrets from 1Password on the VM (not passed to container)
- Injects GITHUB_TOKEN, ATUIN_*, TAILSCALE_* as environment variables
- Copies Claude CLI credentials for seamless authentication
- Uses the 'docker' provider (local Docker on this VM)

Security: Containers do NOT have access to 1Password CLI or service tokens.

EOF
    exit 0
}

# Build devpod args with secret injection
build_devpod_args() {
    local -n args_ref=$1

    # Add secrets as workspace environment variables
    if [[ -n "$GITHUB_TOKEN" ]]; then
        args_ref+=("--workspace-env" "GITHUB_TOKEN=$GITHUB_TOKEN")
        args_ref+=("--workspace-env" "GH_TOKEN=$GITHUB_TOKEN")
    fi

    if [[ -n "$ATUIN_USERNAME" ]]; then
        args_ref+=("--workspace-env" "ATUIN_USERNAME=$ATUIN_USERNAME")
    fi
    if [[ -n "$ATUIN_PASSWORD" ]]; then
        args_ref+=("--workspace-env" "ATUIN_PASSWORD=$ATUIN_PASSWORD")
    fi
    if [[ -n "$ATUIN_KEY" ]]; then
        args_ref+=("--workspace-env" "ATUIN_KEY=$ATUIN_KEY")
    fi

    if [[ -n "$PET_GITHUB_TOKEN" ]]; then
        args_ref+=("--workspace-env" "PET_GITHUB_TOKEN=$PET_GITHUB_TOKEN")
    fi

    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        args_ref+=("--workspace-env" "TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY")
    fi
    if [[ -n "$TAILSCALE_API_KEY" ]]; then
        args_ref+=("--workspace-env" "TAILSCALE_API_KEY=$TAILSCALE_API_KEY")
    fi

    # Non-interactive mode for shell-bootstrap
    args_ref+=("--workspace-env" "SHELL_BOOTSTRAP_NONINTERACTIVE=1")
    # Skip 1Password CLI installation (secrets injected by dp.sh)
    args_ref+=("--workspace-env" "SHELL_BOOTSTRAP_SKIP_1PASSWORD=1")
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
            local workspace_name=$(get_workspace_name "$repo")

            # Read secrets from 1Password
            read_all_secrets

            # Build devpod command
            local devpod_args=(
                "up" "$repo"
                "--provider" "docker"
                "--git-clone-recursive-submodules"
            )

            # Add secret environment variables
            build_devpod_args devpod_args

            # Default to --ide none unless user specified --ide
            local ide_specified=false
            for arg in "$@"; do
                [[ "$arg" == "--ide" ]] && ide_specified=true && break
            done
            [[ "$ide_specified" == "false" ]] && devpod_args+=("--ide" "none")

            # Add any additional arguments passed by user
            devpod_args+=("$@")

            log "Creating workspace for $repo..."
            info "Secrets injected (1Password stays on VM only)"
            devpod "${devpod_args[@]}"

            # Copy Claude credentials after workspace is created
            copy_claude_credentials "$workspace_name"
            ;;

        rebuild)
            if [[ $# -eq 0 ]]; then
                error "Usage: $(basename "$0") rebuild <workspace>"
                exit 1
            fi

            local workspace="$1"
            shift

            # Read secrets from 1Password
            read_all_secrets

            # Build devpod command with recreate flag
            local devpod_args=(
                "up" "$workspace"
                "--provider" "docker"
                "--recreate"
                "--git-clone-recursive-submodules"
            )

            # Add secret environment variables
            build_devpod_args devpod_args

            # Default to --ide none unless user specified --ide
            local ide_specified=false
            for arg in "$@"; do
                [[ "$arg" == "--ide" ]] && ide_specified=true && break
            done
            [[ "$ide_specified" == "false" ]] && devpod_args+=("--ide" "none")

            devpod_args+=("$@")

            log "Rebuilding workspace $workspace..."
            info "Secrets injected (1Password stays on VM only)"
            devpod "${devpod_args[@]}"

            # Copy Claude credentials after workspace is rebuilt
            copy_claude_credentials "$workspace"
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
