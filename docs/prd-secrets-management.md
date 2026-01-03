# PRD: Simplified Secrets Management for DevPods

## Overview
Redesign secrets management to remove 1Password dependency from DevPod containers. Secrets should be managed on dev-vm and passed to containers at creation time, with sensitive tokens removed after use.

## Problem Statement
Current approach:
- 1Password CLI is installed in every container
- `OP_SERVICE_ACCOUNT_TOKEN` is stored in containers at `~/.config/dev_env/op_token`
- Tailscale auth key remains accessible in container after registration
- Containers depend on 1Password for secret access during runtime

Issues:
- Each container has full access to 1Password vault
- Tailscale token persists after registration (security risk)
- Containers require network access to 1Password service
- More attack surface if container is compromised

## Goals
1. Centralize secret management on dev-vm only
2. Pass only needed secrets to containers at creation time
3. Remove sensitive tokens after initial use
4. Allow containers to operate independently (no runtime 1Password dependency)

## Requirements

### 1. Remove 1Password from Containers
- Do NOT install 1Password CLI in devcontainers
- Do NOT pass `OP_SERVICE_ACCOUNT_TOKEN` to containers
- Remove `~/.config/dev_env/op_token` creation from onCreate.sh

### 2. Secret Injection at Creation Time
Secrets should be read on dev-vm and passed to container via environment variables:

```bash
# In dp.sh, read secrets BEFORE creating workspace
GITHUB_TOKEN=$(op read "op://DEV_CLI/GitHub/PAT")
ATUIN_USERNAME=$(op read "op://DEV_CLI/Atuin/username")
ATUIN_PASSWORD=$(op read "op://DEV_CLI/Atuin/password")
ATUIN_KEY=$(op read "op://DEV_CLI/Atuin/key")
TAILSCALE_AUTH_KEY=$(op read "op://DEV_CLI/Tailscale/auth_key")
TAILSCALE_API_KEY=$(op read "op://DEV_CLI/Tailscale/api_key")

# Pass to devpod via --workspace-env
devpod up ... \
  --workspace-env "GITHUB_TOKEN=$GITHUB_TOKEN" \
  --workspace-env "ATUIN_USERNAME=$ATUIN_USERNAME" \
  --workspace-env "ATUIN_PASSWORD=$ATUIN_PASSWORD" \
  --workspace-env "ATUIN_KEY=$ATUIN_KEY" \
  --workspace-env "TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY" \
  --workspace-env "TAILSCALE_API_KEY=$TAILSCALE_API_KEY"
```

### 3. Tailscale Token Cleanup
After Tailscale registration in onCreate.sh:
- Unset `TAILSCALE_AUTH_KEY` environment variable
- Do NOT persist auth key to any file
- API key can be kept (only used for device cleanup, not authentication)

```bash
# In onCreate.sh after tailscale up succeeds
unset TAILSCALE_AUTH_KEY
# Remove from environment file if any
sed -i '/TAILSCALE_AUTH_KEY/d' ~/.bashrc ~/.zshrc 2>/dev/null || true
```

### 4. Persistent Secrets (kept in container)
Some secrets need to persist for shell sessions:
- `GITHUB_TOKEN` / `GH_TOKEN` - for git/gh operations
- `ATUIN_*` - for shell history sync

These should be saved to `~/.config/dev_env/secrets.sh`:
```bash
export GITHUB_TOKEN="..."
export GH_TOKEN="$GITHUB_TOKEN"
export ATUIN_USERNAME="..."
export ATUIN_PASSWORD="..."
export ATUIN_KEY="..."
```

### 5. Transient Secrets (used once, then removed)
- `TAILSCALE_AUTH_KEY` - only for initial registration
- `TAILSCALE_API_KEY` - only for device cleanup

## Implementation

### Phase 1: Update dp.sh wrapper
- Read all secrets from 1Password on dev-vm
- Pass secrets via `--workspace-env` flags
- Remove `OP_SERVICE_ACCOUNT_TOKEN` injection

### Phase 2: Update devcontainer onCreate.sh
- Remove 1Password CLI installation
- Remove op_token file creation
- Read secrets from environment variables (already injected by dp.sh)
- Save persistent secrets to `~/.config/dev_env/secrets.sh`
- Clean up transient secrets after use

### Phase 3: Update devcontainer postStart.sh
- Source `~/.config/dev_env/secrets.sh` for persistent secrets
- No changes needed for Tailscale (already started)

### Phase 4: Remove 1Password from template
- Remove `op` CLI installation from onCreate.sh
- Remove all `op read` commands from template
- Update CLAUDE.md documentation

## Files to Modify

### dev_env repository
| File | Change |
|------|--------|
| `scripts/dp.sh` | Read secrets on VM, pass via workspace-env |

### devcontainer-template repository
| File | Change |
|------|--------|
| `onCreate.sh` | Remove op CLI, use env vars, cleanup transient secrets |
| `postStart.sh` | Source secrets.sh |
| `CLAUDE.md` | Update documentation |

## Security Considerations
1. Secrets are still stored in container filesystem (`~/.config/dev_env/secrets.sh`)
   - File permissions should be 600 (owner read/write only)
   - Consider encryption at rest if needed
2. Tailscale auth key is completely removed after registration
3. Container compromise no longer exposes 1Password access

## Success Criteria
1. Containers start without 1Password CLI installed
2. `op` command not available in containers
3. GitHub, Atuin work via persisted env vars
4. Tailscale registers successfully and auth key is not present after
5. Container can operate fully offline (no 1Password network calls)

## Out of Scope
- Encryption of secrets at rest in container
- Secret rotation mechanism
- Multi-vault support
