# PRD: Dev Environment Consolidation v2.0

## Executive Summary

Consolidate three separate repositories (`dev_env`, `devcontainer-template`, `shell-bootstrap`) into a single, purpose-built `dev_env` repository. The new architecture enforces a strict security model where 1Password access exists only on the VM, with secrets injected into DevPods as environment variables.

## Problem Statement

### Current State
- **3 separate repositories** to maintain with complex interdependencies
- **shell-bootstrap** (1952 lines) installs tools for ALL environments, including unnecessary ones
- **Duplicate functionality** (Claude Code setup in 3 places)
- **Security concerns**: 1Password CLI was being installed in DevPods
- **Complex dependency chain**: DevPod onCreate.sh downloads shell-bootstrap from GitHub URL
- **Outdated documentation** spread across multiple repos, inconsistent with reality
- **Unused scripts** and legacy code cluttering the repos

### Current Repository Structure
```
dev_env/              # VM deployment, devpod management
  scripts/            # 15+ scripts (some unused)
  docs/               # PRDs and configs
  infra/              # Azure Bicep templates

devcontainer-template/  # Git submodule for projects
  devcontainer.json
  onCreate.sh         # Downloads shell-bootstrap from GitHub
  postStart.sh

shell-bootstrap/      # 1952-line monolithic install script
  install.sh          # Installs 20+ tools, configures everything
```

## Goals

1. **Single Repository**: All code in `dev_env`
2. **Purpose-Built Scripts**: Separate scripts for each execution context
3. **Security First**: 1Password ONLY on VM, NEVER in DevPods
4. **Minimal DevPod Footprint**: Only install what's needed in containers
5. **Clean Documentation**: Single source of truth
6. **Public-Safe Repository**: No secrets, safe to share

## Non-Goals

- Supporting environments other than Azure VM + DevPods
- Generic shell configuration for non-dev-env use cases
- Backwards compatibility with external shell-bootstrap users

## Technical Architecture

### Execution Contexts

There are exactly 3 execution contexts, each with specific requirements:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        EXECUTION CONTEXTS                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. AZURE CLOUD SHELL (Deployment)                                       │
│     ├── Persistent storage: ~/clouddrive only                           │
│     ├── Tools needed: az CLI, op CLI, git                               │
│     ├── Purpose: Deploy VM, bootstrap environment                       │
│     └── Script: setup-cloudshell.sh                                     │
│                                                                          │
│  2. DEV-VM (Orchestration)                                              │
│     ├── Full 1Password access via Service Account Token                 │
│     ├── Tools: op CLI, devpod CLI, docker, shell tools                  │
│     ├── Purpose: Manage devpods, read secrets, inject to containers     │
│     └── Scripts: setup-vm.sh, dp.sh                                     │
│                                                                          │
│  3. DEVPOD CONTAINERS (Development)                                     │
│     ├── NO 1Password access (secrets injected as env vars)              │
│     ├── Tools: shell tools, dev tools, Claude Code                      │
│     ├── Purpose: Isolated development environments                      │
│     ├── Network: Tailscale receive-only (can accept SSH, no outbound)   │
│     └── Scripts: devpod-setup.sh (replaces onCreate.sh)                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Security Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SECURITY MODEL                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1PASSWORD VAULT (DEV_CLI)                                              │
│         │                                                                │
│         │ Service Account Token                                          │
│         ▼                                                                │
│  ┌──────────────────────────────────────────┐                           │
│  │              DEV-VM                       │                           │
│  │                                           │                           │
│  │  ~/.config/dev_env/op_token  ◄── Stored  │                           │
│  │                                           │                           │
│  │  dp.sh reads secrets:                     │                           │
│  │    - GITHUB_TOKEN                         │                           │
│  │    - ATUIN_* credentials                  │                           │
│  │    - PET_GITHUB_TOKEN                     │                           │
│  │    - TAILSCALE_AUTH_KEY (tagged)          │                           │
│  │    - Claude credentials (copied)          │                           │
│  │                                           │                           │
│  │  Injects as --workspace-env to DevPod    │                           │
│  └──────────────────────────────────────────┘                           │
│         │                                                                │
│         │ Environment Variables (NOT 1Password token)                    │
│         ▼                                                                │
│  ┌──────────────────────────────────────────┐                           │
│  │           DEVPOD CONTAINER               │                           │
│  │                                           │                           │
│  │  - NO 1Password CLI installed            │                           │
│  │  - NO op token available                  │                           │
│  │  - Secrets only in env vars              │                           │
│  │  - Tailscale: receive-only (tag:devpod)  │                           │
│  │  - Internet access: ALLOWED              │                           │
│  │  - Tailnet outbound: BLOCKED             │                           │
│  │                                           │                           │
│  │  Even if compromised, cannot:             │                           │
│  │    - Access 1Password vault              │                           │
│  │    - Reach other tailnet devices         │                           │
│  │    - Escalate to VM or other containers  │                           │
│  └──────────────────────────────────────────┘                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Tailscale ACL Configuration

```json
{
  "tagOwners": {
    "tag:devpod": ["autogroup:admin"],
    "tag:trusted": ["autogroup:admin"]
  },
  "acls": [
    // Admins can access everything
    {"action": "accept", "src": ["autogroup:admin"], "dst": ["*:*"]},
    // Trusted devices can access everything
    {"action": "accept", "src": ["tag:trusted"], "dst": ["*:*"]},
    // Anyone can SSH to devpods (port 22 only)
    {"action": "accept", "src": ["*"], "dst": ["tag:devpod:22"]}
    // NOTE: No rule allows tag:devpod to reach anything (receive-only)
  ],
  "ssh": [
    // SSH to devpods from trusted sources
    {"action": "accept", "src": ["tag:trusted"], "dst": ["tag:devpod"], "users": ["root", "autogroup:nonroot"]}
  ]
}
```

## Proposed Directory Structure

```
dev_env/
├── README.md                    # Single comprehensive README
├── CLAUDE.md                    # Claude Code instructions
├── LICENSE                      # MIT license
│
├── docs/
│   ├── architecture.md          # Technical architecture details
│   ├── security.md              # Security model documentation
│   ├── troubleshooting.md       # Common issues and solutions
│   └── tailscale-acl.json       # Reference ACL configuration
│
├── infra/                       # Azure infrastructure (unchanged)
│   ├── main.bicep
│   └── modules/
│       ├── vm.bicep
│       └── network.bicep
│
├── scripts/
│   ├── core/                    # Core shared functions
│   │   ├── common.sh            # Logging, colors, utilities
│   │   └── secrets.sh           # Secret reading (VM only)
│   │
│   ├── cloudshell/              # Azure Cloud Shell scripts
│   │   └── setup.sh             # Bootstrap Cloud Shell
│   │
│   ├── vm/                      # VM-specific scripts
│   │   ├── setup.sh             # Initial VM setup
│   │   ├── install-tools.sh     # Install shell tools (zsh, starship, etc.)
│   │   └── configure-tools.sh   # Configure gh, atuin, pet, etc.
│   │
│   ├── devpod/                  # DevPod management scripts
│   │   ├── dp.sh                # Main wrapper (reads secrets, creates devpods)
│   │   ├── start-all.sh         # Start all workspaces
│   │   ├── stop-all.sh          # Stop all workspaces
│   │   └── autostart.service    # Systemd service for auto-start
│   │
│   └── azure/                   # Azure management scripts
│       ├── deploy.sh            # Deploy VM
│       ├── start.sh             # Start VM
│       ├── stop.sh              # Stop VM
│       └── redeploy.sh          # Delete and recreate
│
├── devcontainer/                # DevPod container configuration
│   ├── devcontainer.json        # Container definition
│   ├── setup.sh                 # One-time setup (replaces onCreate.sh)
│   ├── startup.sh               # Every-start script (replaces postStart.sh)
│   ├── install-tools.sh         # Install shell tools (minimal, no 1Password)
│   └── configure-tools.sh       # Configure tools from env vars
│
├── config/                      # Configuration templates
│   ├── zshrc.template           # Zsh configuration
│   ├── starship.toml            # Starship prompt config
│   ├── tmux.conf                # Tmux configuration
│   ├── claude-settings.json     # Claude Code settings
│   ├── claude-statusline.sh     # Claude status bar script
│   └── mcp.json                 # MCP server configuration
│
└── .taskmaster/                 # Task Master configuration
    ├── config.json
    └── tasks/
```

## Detailed Specifications

### 1. Core Scripts (`scripts/core/`)

#### common.sh
Shared utility functions for all scripts:
- Colored logging (log, warn, error, info)
- Command existence checks
- Path utilities
- Error handling

#### secrets.sh (VM ONLY)
Functions for reading secrets from 1Password:
- `read_secret()` - Read a single secret
- `read_all_secrets()` - Read all required secrets
- `validate_secrets()` - Ensure required secrets exist

### 2. Cloud Shell Scripts (`scripts/cloudshell/`)

#### setup.sh
Purpose: Bootstrap Azure Cloud Shell for VM deployment
- Install 1Password CLI to ~/clouddrive/bin/
- Install Claude Code CLI wrapper
- Clone dev_env to ~/clouddrive/
- Configure PATH and aliases

### 3. VM Scripts (`scripts/vm/`)

#### setup.sh
Purpose: Initial VM setup after deployment
1. Prompt for 1Password Service Account Token
2. Save token to ~/.config/dev_env/op_token
3. Verify token works
4. Run install-tools.sh
5. Run configure-tools.sh

#### install-tools.sh
Purpose: Install all shell tools on VM
- apt packages (zsh, git, curl, jq, etc.)
- 1Password CLI (op)
- Starship prompt
- Atuin shell history
- Yazi file manager
- Delta git diff
- Pet snippets
- Claude Code CLI
- DevPod CLI
- Docker & Docker Compose
- Task Master

#### configure-tools.sh
Purpose: Configure tools using 1Password secrets
- Authenticate gh CLI
- Configure git credentials
- Login to Atuin
- Sync Pet snippets
- Configure zsh/starship/tmux

### 4. DevPod Scripts (`scripts/devpod/`)

#### dp.sh (Main Entry Point)
Purpose: Create/manage devpods with secret injection
```bash
# Usage
dp.sh up <repo>        # Create workspace
dp.sh rebuild <ws>     # Rebuild workspace
dp.sh ssh <ws>         # SSH into workspace
dp.sh list             # List workspaces
dp.sh delete <ws>      # Delete workspace
```

Actions:
1. Read secrets from 1Password (on VM)
2. Build devpod command with --workspace-env flags
3. Run devpod command
4. Copy Claude credentials after creation

Injected environment variables:
- `GITHUB_TOKEN` / `GH_TOKEN`
- `ATUIN_USERNAME` / `ATUIN_PASSWORD` / `ATUIN_KEY`
- `PET_GITHUB_TOKEN`
- `TAILSCALE_AUTH_KEY` (tagged, ephemeral)
- `TAILSCALE_API_KEY` (for cleanup)
- `SHELL_BOOTSTRAP_NONINTERACTIVE=1`

### 5. DevContainer Configuration (`devcontainer/`)

#### devcontainer.json
```json
{
  "name": "Dev Environment",
  "image": "mcr.microsoft.com/devcontainers/python:1-3.12-bookworm",
  "runArgs": [
    "--cap-add=NET_ADMIN",
    "--cap-add=NET_RAW",
    "--device=/dev/net/tun"
  ],
  "features": {
    "ghcr.io/devcontainers/features/node:1": {"version": "20"},
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/pre-commit:2": {}
  },
  "onCreateCommand": "bash .devcontainer/setup.sh",
  "postStartCommand": "bash .devcontainer/startup.sh",
  "remoteUser": "vscode"
}
```

#### setup.sh (One-Time Setup)
Purpose: Configure container on creation (NO 1Password)
1. Save injected env vars to ~/.config/dev_env/secrets.sh
2. Run install-tools.sh (minimal tools, no op CLI)
3. Run configure-tools.sh (use env vars, not 1Password)
4. Configure Tailscale (receive-only)
5. Install project dependencies

#### install-tools.sh (Container)
Purpose: Install shell tools in container (MINIMAL)
- Zsh with vi-mode
- Starship prompt
- Atuin shell history
- Yazi file manager
- Glow markdown viewer
- Pet snippets
- Delta git diff
- Claude Code CLI
- Security tools (gitleaks, trivy, bandit)
- Task Master

**NOT installed:**
- 1Password CLI (security)
- Full development environment (already in base image)

#### configure-tools.sh (Container)
Purpose: Configure tools from environment variables
- Authenticate gh CLI using GITHUB_TOKEN
- Login to Atuin using ATUIN_* vars
- Configure Pet snippets using PET_GITHUB_TOKEN
- Configure git credentials
- No 1Password calls (use env vars only)

### 6. Configuration Files (`config/`)

Pre-built configuration files that get copied to appropriate locations:
- **zshrc.template**: Zsh configuration with vi-mode, plugins, aliases
- **starship.toml**: Custom prompt with git status, context info
- **tmux.conf**: Tmux with sensible defaults
- **claude-settings.json**: Claude Code settings
- **claude-statusline.sh**: Custom status bar (model, context %, tasks)
- **mcp.json**: MCP server configuration for Task Master

## Migration Plan

### Phase 1: Create New Structure
1. Create new directory structure in dev_env
2. Extract and refactor scripts from shell-bootstrap
3. Merge devcontainer-template files
4. Write new configuration files

### Phase 2: Implement Core Functionality
1. Implement common.sh utilities
2. Implement secrets.sh for VM
3. Update dp.sh with new structure
4. Create devcontainer setup scripts

### Phase 3: Testing
1. Test Cloud Shell setup
2. Test VM setup from fresh state
3. Test DevPod creation with chess-tutor
4. Verify security model (no op in container)
5. Verify Tailscale receive-only

### Phase 4: Documentation
1. Rewrite README.md
2. Update CLAUDE.md
3. Create architecture.md
4. Create troubleshooting.md

### Phase 5: Cleanup
1. Archive shell-bootstrap repo (or mark deprecated)
2. Archive devcontainer-template repo (or mark deprecated)
3. Remove old scripts from dev_env
4. Final testing and validation

## Success Criteria

1. **Single Repository**: All code in dev_env
2. **Clean Separation**: Scripts organized by execution context
3. **Security Verified**:
   - `which op` fails in DevPod container
   - DevPod cannot ping dev-vm via Tailscale
   - DevPod can access internet
4. **Functionality Preserved**:
   - gh auth works in DevPod
   - Atuin syncs in DevPod
   - Pet snippets work in DevPod
   - Claude Code works in DevPod
5. **Documentation Complete**:
   - README covers all use cases
   - CLAUDE.md accurate and helpful
   - Troubleshooting guide complete

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing devpods | High | Test thoroughly with chess-tutor first |
| Missing functionality | Medium | Detailed script comparison before removing |
| Security regression | High | Automated verification tests |
| Documentation drift | Low | Single source of truth, no duplication |

## Timeline

| Phase | Tasks | Estimate |
|-------|-------|----------|
| 1 | Create structure, refactor scripts | - |
| 2 | Implement core functionality | - |
| 3 | Testing | - |
| 4 | Documentation | - |
| 5 | Cleanup | - |

## Appendix A: Scripts to Remove/Consolidate

### From dev_env/scripts/
| Script | Action | Reason |
|--------|--------|--------|
| cloudshell-helpers.sh | Merge into cloudshell/setup.sh | Consolidation |
| devpod-setup.sh | Remove | Replaced by devcontainer/setup.sh |
| setup-tailscale.sh | Merge into devcontainer/setup.sh | Consolidation |
| ssh-connect.sh | Keep | Useful utility |
| statusline.sh | Move to config/ | Configuration file |

### From shell-bootstrap/
| Function | Action | Reason |
|----------|--------|--------|
| install_op | VM only | Security |
| install_glow | Both | Useful |
| install_delta | Both | Useful |
| install_atuin | Both | Useful |
| install_yazi | Both | Useful |
| install_starship | Both | Useful |
| install_pet | Both | Useful |
| install_zsh_plugins | Both | Useful |
| install_claude_code | Both | Useful |
| configure_op | VM only | Security |
| configure_github | Both (different impl) | - |
| configure_atuin | Both | Useful |
| configure_pet | Both | Useful |

## Appendix B: Environment Variables

### Injected to DevPod by dp.sh
| Variable | Source | Purpose |
|----------|--------|---------|
| `GITHUB_TOKEN` | op://DEV_CLI/GitHub/PAT | Git auth, gh CLI |
| `GH_TOKEN` | Same | Alias |
| `ATUIN_USERNAME` | op://DEV_CLI/Atuin/username | Shell history |
| `ATUIN_PASSWORD` | op://DEV_CLI/Atuin/password | Shell history |
| `ATUIN_KEY` | op://DEV_CLI/Atuin/key | Shell history |
| `PET_GITHUB_TOKEN` | op://DEV_CLI/Pet/PAT | Snippets sync |
| `TAILSCALE_AUTH_KEY` | op://DEV_CLI/Tailscale/devpod_auth_key | Device registration |
| `TAILSCALE_API_KEY` | op://DEV_CLI/Tailscale/api_key | Cleanup old devices |
| `SHELL_BOOTSTRAP_NONINTERACTIVE` | Hardcoded "1" | Skip prompts |

## Appendix C: 1Password Vault Structure

### DEV_CLI Vault Items
| Item | Fields | Required |
|------|--------|----------|
| GitHub | PAT | Yes |
| Atuin | username, password, key | Yes |
| Pet | PAT | Optional |
| Tailscale | auth_key, devpod_auth_key, api_key | Yes |

### Auth Key Requirements
- **auth_key**: For VM (tag:trusted)
- **devpod_auth_key**: For DevPods (tag:devpod, ephemeral)
- **api_key**: For device cleanup (Tailscale API)
