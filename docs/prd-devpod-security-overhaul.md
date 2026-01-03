# PRD: DevPod Security Overhaul - Secrets Isolation & Network Hardening

## Executive Summary

Redesign the DevPod architecture to enable safe, unattended Claude Code execution by:
1. Removing 1Password from containers entirely (VM-only)
2. Restricting devpod Tailscale to receive-only (no outbound to tailnet)
3. Injecting pre-read secrets at creation time
4. Copying Claude credentials to avoid re-authentication
5. Implementing an enhanced status bar for task monitoring

## Problem Statement

### Current Security Risks
- **1Password in containers**: Each devpod has full vault access via `OP_SERVICE_ACCOUNT_TOKEN`
- **Tailscale full access**: Compromised container can reach all tailnet devices
- **Claude running uncontrolled**: AI agent has unrestricted network capabilities
- **Persistent auth tokens**: Tailscale auth key remains after registration

### User Experience Issues
- **Claude re-authentication**: Must authenticate Claude CLI in each new devpod
- **Status bar limitations**: Current statusline doesn't show task progress, context window broken
- **No visibility**: No way to monitor background tasks or agent activity

## Goals

1. **Zero 1Password access in containers** - Keep `op` CLI and token on dev-vm only
2. **Network isolation for devpods** - Can access internet, but NOT other tailnet devices
3. **Seamless Claude setup** - Copy credentials so no re-auth needed
4. **Enhanced monitoring** - Status bar shows tasks, agents, context (not cost)
5. **Verified working** - Test with chess-tutor repo to confirm all tools work

## Architecture

### Current Flow
```
dev-vm (has op token)
    └─→ dp.sh passes OP_SERVICE_ACCOUNT_TOKEN to devpod
        └─→ Container has full 1Password access
        └─→ Container has full Tailscale network access
```

### New Flow
```
dev-vm (has op token, reads all secrets)
    └─→ dp.sh reads secrets from 1Password
    └─→ dp.sh passes individual secrets as env vars
    └─→ dp.sh copies Claude credentials
        └─→ Container has NO 1Password access
        └─→ Container can ONLY receive Tailscale connections (tag:devpod)
        └─→ Container can access public internet normally
        └─→ Claude is pre-authenticated
```

## Requirements

### 1. Remove 1Password from DevPods

**Changes to dp.sh** (on dev-vm):
```bash
# Read ALL secrets on VM before creating workspace
GITHUB_TOKEN=$(op read "op://DEV_CLI/GitHub/PAT")
ATUIN_USERNAME=$(op read "op://DEV_CLI/Atuin/username")
ATUIN_PASSWORD=$(op read "op://DEV_CLI/Atuin/password")
ATUIN_KEY=$(op read "op://DEV_CLI/Atuin/key")
PET_GITHUB_TOKEN=$(op read "op://DEV_CLI/Pet/PAT" 2>/dev/null || echo "")
TAILSCALE_AUTH_KEY=$(op read "op://DEV_CLI/Tailscale/devpod_auth_key")  # NEW: tagged key
TAILSCALE_API_KEY=$(op read "op://DEV_CLI/Tailscale/api_key")

# Pass to devpod via --workspace-env (NOT OP_SERVICE_ACCOUNT_TOKEN)
devpod up "$REPO" \
  --workspace-env "GITHUB_TOKEN=$GITHUB_TOKEN" \
  --workspace-env "GH_TOKEN=$GITHUB_TOKEN" \
  --workspace-env "ATUIN_USERNAME=$ATUIN_USERNAME" \
  --workspace-env "ATUIN_PASSWORD=$ATUIN_PASSWORD" \
  --workspace-env "ATUIN_KEY=$ATUIN_KEY" \
  --workspace-env "PET_GITHUB_TOKEN=$PET_GITHUB_TOKEN" \
  --workspace-env "TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY" \
  --workspace-env "TAILSCALE_API_KEY=$TAILSCALE_API_KEY" \
  --workspace-env "SHELL_BOOTSTRAP_NONINTERACTIVE=1" \
  --ide none \
  --provider docker
```

**Changes to devcontainer-template**:
- Remove 1Password CLI installation from onCreate.sh
- Remove all `op read` commands
- Use environment variables directly
- Save persistent secrets to `~/.config/dev_env/secrets.sh`

### 2. Tailscale Receive-Only Configuration

**Concept**: DevPods should:
- ✅ Accept incoming SSH connections from other tailnet devices
- ✅ Access the public internet (for npm, pip, git clone, etc.)
- ❌ NOT initiate connections to other tailnet devices (VM, other devpods)

**Implementation using ACL Tags**:

#### Step 1: Create a `tag:devpod` in Tailscale ACL
```json
{
  "tagOwners": {
    "tag:devpod": ["autogroup:admin"],
    "tag:trusted": ["autogroup:admin"]
  }
}
```

#### Step 2: Create ACL Rules (devpod as destination only)
```json
{
  "acls": [
    // Trusted devices (VM, personal machines) can access everything
    {
      "action": "accept",
      "src": ["tag:trusted", "autogroup:member"],
      "dst": ["*:*"]
    },
    // DevPods can ONLY be accessed, they cannot initiate connections
    // (No rule has tag:devpod as src, so they can't connect to tailnet)
  ]
}
```

#### Step 3: Create Tagged Ephemeral Auth Key
In Tailscale Admin Console:
1. Go to Settings → Keys → Generate auth key
2. Check "Ephemeral" (device auto-removed when offline)
3. Check "Pre-authorized" (no manual approval needed)
4. Select tag: `tag:devpod`
5. Save to 1Password as `op://DEV_CLI/Tailscale/devpod_auth_key`

**Why this is safe**:
- The auth key is used once during `tailscale up`
- After registration, the key is discarded (unset from environment)
- The device is tagged `tag:devpod` which has NO outbound permissions
- Device is ephemeral - auto-removed from tailnet when container stops
- ACL rules are enforced by Tailscale infrastructure, not the device

**Full Tailscale ACL Policy**:
```json
{
  "tagOwners": {
    "tag:devpod": ["autogroup:admin"],
    "tag:trusted": ["autogroup:admin"]
  },
  "autoApprovers": {
    "routes": {}
  },
  "acls": [
    // Admin and trusted devices have full access
    {
      "action": "accept",
      "src": ["autogroup:admin", "tag:trusted"],
      "dst": ["*:*"]
    },
    // Regular members can access devpods (SSH) and trusted servers
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:devpod:22", "tag:trusted:*"]
    }
    // NOTE: No rule allows tag:devpod as src
    // This means devpods CANNOT initiate tailnet connections
    // They CAN still access public internet (not controlled by ACL)
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:admin", "autogroup:member"],
      "dst": ["tag:devpod"],
      "users": ["root", "autogroup:nonroot"]
    }
  ]
}
```

### 3. Claude Credential Copying

**Credential Location**: `~/.claude/.credentials.json`

**dp.sh additions** (after devpod up succeeds):
```bash
# Copy Claude credentials to devpod
CLAUDE_CREDS="$HOME/.claude/.credentials.json"
if [[ -f "$CLAUDE_CREDS" ]]; then
  echo "Copying Claude credentials to devpod..."
  # Create .claude directory in devpod
  devpod ssh "$WORKSPACE" -- "mkdir -p ~/.claude && chmod 700 ~/.claude"
  # Copy credentials file
  cat "$CLAUDE_CREDS" | devpod ssh "$WORKSPACE" -- "cat > ~/.claude/.credentials.json && chmod 600 ~/.claude/.credentials.json"
  echo "Claude credentials copied successfully"
fi
```

**Security considerations**:
- OAuth tokens (not API keys) - more secure
- Refresh token enables auto-renewal
- File permissions set to 600
- Tokens are per-user, not per-machine

### 4. Git Authentication Setup

**Use `gh` for git credential management** (not separate git tokens):

```bash
# In devcontainer onCreate.sh (using injected GITHUB_TOKEN)
export GH_TOKEN="$GITHUB_TOKEN"

# Configure gh CLI
gh auth setup-git

# This configures git to use gh as credential helper:
# git config --global credential.helper "!gh auth git-credential"
```

**Benefits**:
- Single token for both gh CLI and git operations
- No separate git credential storage
- Works for both HTTPS and gh-authenticated operations

### 5. Pet Snippet Sync

**Pet** stores snippets in a GitHub Gist. Configuration:

```bash
# In onCreate.sh (using injected PET_GITHUB_TOKEN)
if [[ -n "$PET_GITHUB_TOKEN" ]]; then
  mkdir -p ~/.config/pet
  cat > ~/.config/pet/config.toml << EOF
[General]
  snippetfile = "$HOME/.config/pet/snippet.toml"
  editor = "vim"
  column = 40
  selectcmd = "fzf"
  backend = "gist"
  sortby = "recency"

[Gist]
  file_name = "pet-snippet.toml"
  access_token = "$PET_GITHUB_TOKEN"
  gist_id = ""
  public = false
  auto_sync = true
EOF
  # Sync snippets
  pet sync
fi
```

### 6. Enhanced Claude Status Bar

**Requirements**:
- Show current/background tasks (from TodoWrite tool)
- Show agent status (running subagents)
- Show context window usage (percentage, tokens remaining)
- Do NOT show cost information
- Fix broken context percentage display

**Implementation using ccstatusline**:

Create `~/.claude/statusline.sh`:
```bash
#!/bin/bash
# Parse JSON input from Claude Code
INPUT=$(cat)

# Extract values
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "Unknown"')
CONTEXT_USED=$(echo "$INPUT" | jq -r '.usage.context_tokens // 0')
CONTEXT_MAX=$(echo "$INPUT" | jq -r '.usage.context_limit // 200000')
CONTEXT_PCT=$(echo "scale=1; $CONTEXT_USED * 100 / $CONTEXT_MAX" | bc)

# Current directory (abbreviated)
DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "~"' | sed "s|$HOME|~|")
DIR_SHORT=$(echo "$DIR" | rev | cut -d'/' -f1-2 | rev)

# Git branch
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

# Task count from todo (if available)
TODOS_FILE="$HOME/.claude/todos/current.json"
if [[ -f "$TODOS_FILE" ]]; then
  TOTAL_TASKS=$(jq '.todos | length' "$TODOS_FILE" 2>/dev/null || echo 0)
  DONE_TASKS=$(jq '[.todos[] | select(.status=="completed")] | length' "$TODOS_FILE" 2>/dev/null || echo 0)
  IN_PROGRESS=$(jq '[.todos[] | select(.status=="in_progress")] | length' "$TODOS_FILE" 2>/dev/null || echo 0)
  TASK_INFO="[$DONE_TASKS/$TOTAL_TASKS"
  [[ "$IN_PROGRESS" -gt 0 ]] && TASK_INFO="$TASK_INFO +$IN_PROGRESS"
  TASK_INFO="$TASK_INFO]"
else
  TASK_INFO=""
fi

# Build status line
echo -n "$MODEL | $DIR_SHORT"
[[ -n "$GIT_BRANCH" ]] && echo -n " ($GIT_BRANCH)"
echo -n " | ctx:${CONTEXT_PCT}%"
[[ -n "$TASK_INFO" ]] && echo -n " $TASK_INFO"
```

**Alternative: Use ccstatusline** (recommended):
```json
// ~/.claude/settings.json
{
  "statusLine": {
    "type": "command",
    "command": "bunx ccstatusline@latest",
    "padding": 0
  }
}
```

Then configure ccstatusline widgets:
- Model Name
- Working Directory (fish-style abbreviated)
- Git Branch
- Context Percentage (remaining mode)
- Custom Command (for task count)

**ccstatusline configuration** (`~/.config/ccstatusline/settings.json`):
```json
{
  "lines": [
    {
      "widgets": [
        {"type": "model_name"},
        {"type": "separator", "value": " | "},
        {"type": "working_directory", "segments": 2, "fish_style": true},
        {"type": "separator", "value": " "},
        {"type": "git_branch"},
        {"type": "flex_separator"},
        {"type": "context_percentage", "remaining": true},
        {"type": "separator", "value": " "},
        {"type": "custom_command", "command": "~/.claude/task-count.sh"}
      ]
    }
  ],
  "global": {
    "powerline": false,
    "padding": 1
  }
}
```

### 7. Secret Persistence in Container

**File**: `~/.config/dev_env/secrets.sh` (chmod 600)

```bash
# Persistent secrets (sourced by shell)
export GITHUB_TOKEN="..."
export GH_TOKEN="$GITHUB_TOKEN"
export ATUIN_USERNAME="..."
export ATUIN_PASSWORD="..."
export ATUIN_KEY="..."
export PET_GITHUB_TOKEN="..."
```

**File**: `~/.config/dev_env/init.sh` (sourced by .zshrc/.bashrc)

```bash
# Source secrets if available
[[ -f ~/.config/dev_env/secrets.sh ]] && source ~/.config/dev_env/secrets.sh
```

**Transient secrets** (used once, then discarded):
- `TAILSCALE_AUTH_KEY` - unset after `tailscale up`
- `TAILSCALE_API_KEY` - unset after device cleanup

## Files to Modify

### dev_env Repository

| File | Changes |
|------|---------|
| `scripts/dp.sh` | Read secrets from 1Password, pass as env vars, copy Claude creds |
| `CLAUDE.md` | Update documentation for new flow |
| `docs/prd-devpod-security-overhaul.md` | This PRD |

### devcontainer-template Repository

| File | Changes |
|------|---------|
| `onCreate.sh` | Remove op CLI, use env vars, setup gh/atuin/pet, cleanup transient secrets |
| `postStart.sh` | Source secrets.sh |
| `devcontainer.json` | Remove 1Password feature |

### Tailscale Admin Console

| Setting | Changes |
|---------|---------|
| ACL Policy | Add tag:devpod, restrict ACL rules |
| Auth Keys | Create tagged ephemeral key for devpods |

### 1Password Vault (DEV_CLI)

| Item | Field | Purpose |
|------|-------|---------|
| `Tailscale` | `devpod_auth_key` | NEW: Tagged ephemeral key for devpods |
| `Tailscale` | `auth_key` | Keep: For dev-vm (full access) |
| `Pet` | `PAT` | Optional: For snippet sync |

## Testing Requirements

### Test Environment
- **Test repo**: `https://github.com/kirderfg/chess-tutor`
- **Test command**: `~/dev_env/scripts/dp.sh up https://github.com/kirderfg/chess-tutor`

### Test Cases

#### TC1: DevPod Creation Without 1Password
```bash
# After devpod up completes
devpod ssh chess-tutor -- "which op"
# Expected: command not found

devpod ssh chess-tutor -- "echo \$OP_SERVICE_ACCOUNT_TOKEN"
# Expected: empty/unset
```

#### TC2: GitHub Authentication
```bash
devpod ssh chess-tutor -- "gh auth status"
# Expected: Logged in to github.com

devpod ssh chess-tutor -- "git clone https://github.com/kirderfg/private-repo.git /tmp/test"
# Expected: Clone succeeds (if private repo exists)
```

#### TC3: Atuin Shell History
```bash
devpod ssh chess-tutor -- "su - vscode -c 'atuin status'"
# Expected: Shows sync status, username

devpod ssh chess-tutor -- "su - vscode -c 'atuin sync'"
# Expected: Sync succeeds
```

#### TC4: Pet Snippets
```bash
devpod ssh chess-tutor -- "su - vscode -c 'pet list'"
# Expected: Shows snippets (if configured)
```

#### TC5: Tailscale Receive-Only
```bash
# From devpod, try to connect to dev-vm
devpod ssh chess-tutor -- "tailscale ping dev-vm"
# Expected: FAIL (no permission to initiate connection)

# From dev-vm, connect to devpod
ssh root@devpod-chess-tutor
# Expected: SUCCESS

# From devpod, access internet
devpod ssh chess-tutor -- "curl -s https://api.github.com/zen"
# Expected: SUCCESS (returns GitHub zen message)
```

#### TC6: Claude Authentication
```bash
devpod ssh chess-tutor -- "su - vscode -c 'claude --version'"
# Expected: Shows version

devpod ssh chess-tutor -- "su - vscode -c 'cat ~/.claude/.credentials.json | jq .claudeAiOauth.subscriptionType'"
# Expected: "max" (or your subscription type)
```

#### TC7: Tailscale Auth Key Cleanup
```bash
devpod ssh chess-tutor -- "env | grep TAILSCALE_AUTH"
# Expected: Nothing (key was unset after registration)

devpod ssh chess-tutor -- "grep -r TAILSCALE_AUTH ~/.config ~/.bashrc ~/.zshrc 2>/dev/null"
# Expected: Nothing found
```

#### TC8: Status Bar Functionality
```bash
# Inside devpod, run Claude and verify status bar shows:
# - Model name
# - Context percentage (working, not "NaN%" or broken)
# - Task count (if todos exist)
# - Git branch (if in repo)
# - NO cost information
```

## Implementation Phases

### Phase 1: Tailscale ACL Configuration
1. Create `tag:devpod` in Tailscale ACL
2. Update ACL rules to restrict devpod outbound
3. Create tagged ephemeral auth key
4. Save new key to 1Password
5. Test ACL enforcement manually

### Phase 2: Update dp.sh
1. Read all secrets from 1Password on VM
2. Pass secrets via `--workspace-env`
3. Remove `OP_SERVICE_ACCOUNT_TOKEN` injection
4. Add Claude credential copying
5. Test devpod creation

### Phase 3: Update devcontainer-template
1. Remove 1Password CLI installation
2. Update onCreate.sh to use env vars
3. Setup gh auth with injected token
4. Setup atuin with injected credentials
5. Setup pet with injected token
6. Cleanup transient secrets
7. Test all tools work

### Phase 4: Status Bar Enhancement
1. Install ccstatusline or create custom script
2. Configure widgets (no cost, yes context/tasks)
3. Test context percentage display
4. Add task count widget
5. Deploy to devcontainer template

### Phase 5: Integration Testing
1. Delete existing chess-tutor devpod
2. Create fresh devpod with new flow
3. Run all test cases
4. Document any issues
5. Fix and re-test

### Phase 6: Documentation
1. Update CLAUDE.md
2. Update README.md
3. Remove old 1Password instructions
4. Add troubleshooting section

## Security Considerations

### Secrets at Rest
- `~/.config/dev_env/secrets.sh` has chmod 600
- Consider encryption if higher security needed
- Secrets persist across container restarts

### Tailscale Network Isolation
- ACL rules enforced at Tailscale infrastructure level
- Device cannot bypass restrictions locally
- Ephemeral nodes auto-cleanup on disconnect

### Claude Credentials
- OAuth tokens with limited scope
- Refresh token enables renewal
- Not API keys (more restrictive)

### Attack Surface Reduction
- No 1Password CLI = no vault access if compromised
- No outbound tailnet = can't pivot to other machines
- Transient tokens discarded = no reuse possible

## Success Criteria

1. ✅ `op` command not available in devpods
2. ✅ `OP_SERVICE_ACCOUNT_TOKEN` not present in devpod environment
3. ✅ `gh auth status` shows authenticated
4. ✅ `git clone` works for private repos
5. ✅ `atuin sync` works
6. ✅ `pet list` works (if configured)
7. ✅ `tailscale ping dev-vm` fails from devpod
8. ✅ `ssh root@devpod-*` works from dev-vm
9. ✅ Internet access works from devpod
10. ✅ Claude is pre-authenticated (no login prompt)
11. ✅ Status bar shows context %, tasks, no cost
12. ✅ Tailscale auth key not present after registration

## Out of Scope

- Encryption of secrets at rest
- Secret rotation mechanism
- Multi-vault support
- Custom ACL per-devpod (all devpods share tag:devpod)
- Windows devpod support

## References

- [Tailscale ACL Documentation](https://tailscale.com/kb/1018/acls)
- [Tailscale Tags](https://tailscale.com/kb/1068/tags)
- [Tailscale Auth Keys](https://tailscale.com/kb/1085/auth-keys)
- [Tailscale Ephemeral Nodes](https://tailscale.com/kb/1111/ephemeral-nodes)
- [ccstatusline GitHub](https://github.com/sirmalloc/ccstatusline)
- [Claude Code Status Line Docs](https://code.claude.com/docs/en/statusline)
