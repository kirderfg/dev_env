# Azure Spot VM Development Environment

A cost-effective Azure Spot VM for container development in Sweden Central, with DevPod integration for managing devcontainers remotely.

## Specs

| Component | Value |
|-----------|-------|
| VM Size | Standard_D4s_v5 (4 vCPU, 16GB RAM) |
| OS | Ubuntu 24.04 LTS |
| Disk | 64GB Premium SSD |
| Region | Sweden Central |
| Spot Config | maxPrice: -1 (pay up to on-demand, evict on capacity only) |
| Eviction | Deallocate (preserves disk) |

## Cost Estimate

- Spot VM: ~$0.05/hr
- Disk: ~$10/mo
- Public IP: ~$3.65/mo
- **Total (24/7)**: ~$50/mo
- **Total (8hr/day)**: ~$25/mo

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- Azure subscription with permissions to create VMs

## Quick Start

```bash
# 1. Login to Azure
az login

# 2. Run setup (installs DevPod, deploys VM, configures everything)
./setup.sh

# 3. Start coding!
devpod up github.com/your/repo --provider ssh --provider-option HOST=dev-vm --ide vscode
```

### Manual Setup

If you prefer to run steps individually:

```bash
./scripts/deploy.sh        # Deploy VM only
./scripts/devpod-setup.sh  # Configure DevPod only
./scripts/ssh-connect.sh   # SSH into VM
```

## Scripts

| Script | Description |
|--------|-------------|
| `setup.sh` | **One-command setup**: installs DevPod, deploys VM, configures everything |
| `scripts/deploy.sh` | Deploy/update infrastructure, auto-generates SSH key |
| `scripts/redeploy.sh` | Delete and recreate VM from scratch |
| `scripts/ssh-connect.sh` | SSH into the VM |
| `scripts/start-vm.sh` | Start a deallocated VM |
| `scripts/stop-vm.sh` | Stop and deallocate VM (saves compute costs) |
| `scripts/sync-secrets.sh` | Sync 1Password service account token to VM |
| `scripts/devpod-setup.sh` | Configure DevPod SSH provider for this VM |

## DevPod Integration

[DevPod](https://devpod.sh) lets you run devcontainers on your remote VM while developing locally. Think "GitHub Codespaces, but self-hosted and open-source."

### Quick Install

```bash
# One command sets up everything (DevPod + VM + configuration)
az login
./setup.sh
```

That's it! Now jump to [Usage](#usage).

### How It Works

```
┌─────────────────┐         SSH          ┌─────────────────────────────┐
│  Local Machine  │◄───────────────────►│        Azure Spot VM         │
│                 │                      │                              │
│  - DevPod CLI   │                      │  ┌────────────────────────┐ │
│  - VS Code      │                      │  │    DevContainer        │ │
│  - Terminal     │                      │  │  ┌──────────────────┐  │ │
│                 │                      │  │  │ Your Project     │  │ │
└─────────────────┘                      │  │  │ + Dev Tools      │  │ │
                                         │  │  │ + Dependencies   │  │ │
                                         │  │  └──────────────────┘  │ │
                                         │  └────────────────────────┘ │
                                         │         Docker              │
                                         └─────────────────────────────┘
```

Your code runs in a container on the VM, but you edit locally with full IDE support.

### Prerequisites

**Azure CLI** - [Install instructions](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

Everything else is installed automatically by `./setup.sh`.

<details>
<summary>Manual DevPod installation (if needed)</summary>

```bash
# Linux (amd64)
curl -L -o devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
sudo install -c -m 0755 devpod /usr/local/bin && rm devpod

# Linux (arm64)
curl -L -o devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-arm64"
sudo install -c -m 0755 devpod /usr/local/bin && rm devpod

# macOS
brew install devpod

# Windows
winget install DevPod
```

More info: https://devpod.sh/docs/getting-started/install
</details>

### Setup

```bash
# One command does everything
./setup.sh
```

**What it does:**
1. Installs DevPod CLI to `~/.local/bin` (if not present)
2. Deploys Azure Spot VM (if not exists)
3. Adds SSH config entry `dev-vm`
4. Configures DevPod SSH provider

### Usage

#### Terminal-Only Workflow (No IDE)

```bash
# 1. Create workspace from a GitHub repo
devpod up github.com/your/repo --provider ssh --provider-option HOST=dev-vm --ide none

# 2. SSH into the workspace
devpod ssh your-repo

# 3. You're now inside the devcontainer on your VM - code away!
#    The repo is at /workspaces/your-repo
```

**Full example session:**
```bash
$ devpod up github.com/microsoft/vscode-remote-try-go --provider ssh --provider-option HOST=dev-vm --ide none
# ... builds container ...

$ devpod ssh vscode-remote-try-go
root@devcontainer:/workspaces/vscode-remote-try-go# go run server.go
```

#### With VS Code

```bash
# Opens VS Code connected to the devcontainer
devpod up github.com/your/repo --provider ssh --provider-option HOST=dev-vm --ide vscode
```

#### From Local Folder

```bash
# Syncs local folder to VM and creates devcontainer
devpod up ./my-project --provider ssh --provider-option HOST=dev-vm --ide none

# Then connect
devpod ssh my-project
```

#### Port Forwarding

Ports defined in devcontainer.json are **automatically forwarded**:

```json
{
  "forwardPorts": [3000, 5432]
}
```

```bash
devpod ssh my-workspace
# localhost:3000 and localhost:5432 just work
```

**Ad-hoc forwarding** (for ports not in devcontainer.json):

```bash
devpod ssh my-workspace -L 8080:localhost:8080
```

#### Manage Workspaces

```bash
# List all workspaces
devpod list

# SSH into existing workspace
devpod ssh my-workspace

# Stop workspace (container stops, data preserved)
devpod stop my-workspace

# Start stopped workspace
devpod up my-workspace --ide none

# Delete workspace completely
devpod delete my-workspace
```

### devcontainer.json Example

Add this to your project at `.devcontainer/devcontainer.json`:

```json
{
  "name": "My Dev Environment",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/go:1": {},
    "ghcr.io/devcontainers/features/docker-in-docker:2": {}
  },
  "forwardPorts": [3000, 8080],
  "customizations": {
    "vscode": {
      "extensions": ["golang.go"]
    }
  },
  "postCreateCommand": "go mod download"
}
```

### Tips

- **First workspace is slow**: DevPod downloads its agent and builds the container. Subsequent starts are fast.
- **Workspace persistence**: Workspaces survive VM restarts. After `./scripts/start-vm.sh`, just `devpod up my-workspace`.
- **Port forwarding**: DevPod auto-forwards ports. Access `localhost:3000` on your machine for a service running in the container.
- **Multiple workspaces**: Run several projects on the same VM, each in isolated containers.

## After Eviction

If Azure reclaims the VM due to capacity:

```bash
# Check VM status
az vm show -g rg-dev-env -n vm-dev --query "powerState" -o tsv

# Restart the VM
./scripts/start-vm.sh
```

The disk is preserved, so all your data remains intact.

## Secrets Management (1Password)

Secrets are managed via **1Password CLI** - they are fetched on-demand and never stored as plaintext files.

### Initial Setup

1. **Create a 1Password Service Account** at: 1Password → Settings → Developer → Service Accounts
2. **Grant access** to your `DEV_CLI` vault (or create one)
3. **Run shell-bootstrap locally** - it will prompt for your token:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/install.sh
   bash /tmp/install.sh
   ```

### Required 1Password Items

Create these items in your `DEV_CLI` vault:

| Item | Field | Description |
|------|-------|-------------|
| `Atuin` | `username` | Atuin sync username |
| `Atuin` | `password` | Atuin sync password |
| `Atuin` | `key` | Atuin encryption key (from `atuin key`) |
| `Pet` | `PAT` | Pet snippets GitHub token |
| `OpenAI` | `api_key` | OpenAI API key |
| `GitHub` | `PAT` | GitHub Personal Access Token (for gh CLI + git auth) |

### Token Flow

The 1Password Service Account Token must be provided to each environment:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TOKEN FLOW OVERVIEW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  LOCAL MACHINE                                                              │
│  └── ~/.config/dev_env/op_token  ◄── Created by shell-bootstrap            │
│            │                                                                │
│            ├──────────────────────────────────────────┐                     │
│            │                                          │                     │
│            ▼                                          ▼                     │
│  ┌─────────────────────┐                ┌──────────────────────────────┐   │
│  │     AZURE VM        │                │     DEVPOD CONTAINER         │   │
│  │                     │                │                              │   │
│  │  sync-secrets.sh    │                │  --workspace-env passes      │   │
│  │  copies token to:   │                │  OP_SERVICE_ACCOUNT_TOKEN    │   │
│  │  ~/.config/dev_env/ │                │  to container environment    │   │
│  │  op_token           │                │                              │   │
│  │                     │                │  shell-bootstrap picks up    │   │
│  │  Token persists on  │                │  token from env var and      │   │
│  │  VM disk (survives  │                │  configures everything       │   │
│  │  restarts)          │                │                              │   │
│  └─────────────────────┘                └──────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### For Azure VM

After deploying the VM, sync your token once:

```bash
./scripts/sync-secrets.sh
```

The token is saved to the VM and persists across restarts. shell-bootstrap loads it on every shell start.

#### For DevPod Containers

Pass the token when creating workspaces:

```bash
# Create workspace with secrets
devpod up github.com/your/repo --provider ssh --provider-option HOST=dev-vm \
  --ide none --workspace-env OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/dev_env/op_token) \
  --workspace-env SHELL_BOOTSTRAP_NONINTERACTIVE=1

# Or from local folder
devpod up ./my-project --provider ssh --provider-option HOST=dev-vm \
  --ide none --workspace-env OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/dev_env/op_token) \
  --workspace-env SHELL_BOOTSTRAP_NONINTERACTIVE=1
```

**Tip:** Use `pet` snippets (Ctrl+S) for quick access to these commands.

### What Gets Configured

When the token is available, shell-bootstrap automatically:
- Authenticates GitHub CLI (`gh auth login`)
- Configures git credential helper (HTTPS auth via `gh`)
- Logs into Atuin (shell history sync)
- Syncs pet snippets from private repo
- Exports `OPENAI_API_KEY`, `GITHUB_TOKEN` to environment

### Manual Secret Access

```bash
# Read a specific secret
op read 'op://DEV_CLI/OpenAI/api_key'

# Run a command with secrets injected
op run --env-file=.env.tpl -- ./my-script.sh
```

### Architecture

```
┌─────────────────────┐
│   1Password Cloud   │
│   (DEV_CLI vault)   │
└──────────┬──────────┘
           │ HTTPS (encrypted)
           ▼
┌─────────────────────────────────────────────┐
│  VM / DevContainer                          │
│  ┌───────────────────────────────────────┐  │
│  │  op CLI + Service Account Token       │  │
│  │                                       │  │
│  │  Shell init:                          │  │
│  │    source ~/.config/dev_env/init.sh   │  │
│  │    → exports OPENAI_API_KEY, etc.     │  │
│  │    → authenticates gh CLI             │  │
│  │    → configures git credentials       │  │
│  │                                       │  │
│  │  ✓ Secrets fetched on-demand          │  │
│  │  ✓ Only in memory, never on disk      │  │
│  │  ✓ Audit trail in 1Password           │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Security

- SSH key authentication only (no passwords)
- NSG restricts SSH to your IP address
- All other inbound traffic denied
- Secrets managed via 1Password (never stored as plaintext)

## Pre-installed Tools

The VM comes with:
- Docker & Docker Compose
- GitHub CLI (`gh`)
- 1Password CLI (`op`)
- Git, curl, vim, tmux, htop, jq, unzip

## DevContainer Template

The `templates/devcontainer/` folder contains a best-practices template for Python + Node projects:

```bash
# Copy to your project
cp -r templates/devcontainer/.devcontainer your-project/
cp templates/devcontainer/.pre-commit-config.yaml your-project/
```

**Includes:**
- Python 3.12, Node 20, Docker-in-Docker
- GitHub CLI, pre-commit hooks
- Security scanning: Gitleaks, Trivy, Bandit, Safety
- VS Code extensions: Python, ESLint, Prettier, Snyk, GitLens

See [templates/devcontainer/README.md](templates/devcontainer/README.md) for details.

## File Structure

```
dev_env/
├── setup.sh                    # One-command setup
├── infra/
│   ├── main.bicep              # Main orchestration
│   └── modules/
│       ├── vm.bicep            # Spot VM + cloud-init
│       └── network.bicep       # VNet, NSG, Public IP
├── scripts/
│   ├── deploy.sh               # Deploy VM infrastructure
│   ├── redeploy.sh             # Delete and recreate VM
│   ├── ssh-connect.sh          # SSH into VM
│   ├── start-vm.sh             # Start deallocated VM
│   ├── stop-vm.sh              # Stop and deallocate VM
│   ├── sync-secrets.sh         # Sync 1Password token to VM
│   └── devpod-setup.sh         # Configure DevPod SSH provider
├── templates/
│   └── devcontainer/           # DevContainer template
├── .env                        # VM config (auto-generated)
└── README.md
```

## Cleanup

To delete all resources:

```bash
az group delete --name rg-dev-env --yes --no-wait
```
