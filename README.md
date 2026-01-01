# Azure VM Development Environment

A cost-effective Azure VM for container development in Sweden Central, with DevPod integration for managing devcontainers remotely.

## Specs

| Component | Value |
|-----------|-------|
| VM Size | Standard_D4s_v5 (4 vCPU, 16GB RAM) |
| OS | Ubuntu 24.04 LTS |
| Disk | 64GB Premium SSD |
| Region | Sweden Central |
| Pricing: Regular (on-demand) |
| |

## Cost Estimate

- VM: ~$0.05/hr
- Disk: ~$10/mo
- Public IP: ~$3.65/mo
- **Total (24/7)**: ~$50/mo
- **Total (8hr/day)**: ~$25/mo

## Prerequisites

- Azure subscription with permissions to create VMs
- 1Password account with Service Account Token
- Required 1Password items in `DEV_CLI` vault (see [1Password Setup](#1password-setup))

## 1Password Setup

### Required Items in `DEV_CLI` Vault

| Item | Type | Fields | Purpose |
|------|------|--------|---------|
| `GitHub` | Login | `PAT` | Clone private repos |
| `Tailscale` | Login | `auth_key`, `api_key` | VM + container networking |

### Create Service Account Token

1. Go to [1Password.com](https://1password.com) → Settings → Developer → Service Accounts
2. Create a new Service Account
3. Grant access to the `DEV_CLI` vault
4. Copy the token (starts with `ops_eyJ...`)

### Connecting to the VM

The VM has **no public SSH access** - all connections go through Tailscale.

**Step 1: Install Tailscale on your machine**

- Windows/Mac/Linux: [tailscale.com/download](https://tailscale.com/download)
- iPhone/Android: App Store / Play Store

**Step 2: Configure SSH (optional, for convenience)**

Add to `~/.ssh/config`:
```
Host dev-vm
    HostName dev-vm
    User azureuser
```

**Step 3: Connect**

```bash
ssh dev-vm
# Or directly:
ssh azureuser@dev-vm
```

No SSH keys needed - Tailscale SSH handles authentication based on your Tailscale identity.

## Quick Start (Azure Cloud Shell)

The easiest way to deploy - no local setup required:

**1. Open Azure Cloud Shell**
- Go to [portal.azure.com](https://portal.azure.com)
- Click the Cloud Shell icon (>_) in the top navigation bar
- Select **Bash** if prompted

**2. Deploy the VM**
```bash
git clone https://github.com/kirderfg/dev_env.git
cd dev_env
./scripts/deploy.sh
```

The script prompts for your 1Password token, fetches Tailscale keys, and deploys the VM.

**3. Setup the VM**
```bash
# SSH to VM via Tailscale
ssh azureuser@dev-vm

# Clone dev_env and run setup
git clone https://github.com/kirderfg/dev_env.git ~/dev_env
~/dev_env/scripts/setup-vm.sh
```

**4. Start coding**
```bash
# Create a devpod
~/dev_env/scripts/dp.sh up https://github.com/your/repo
```

Note: The VM has no public SSH access. All connections go through Tailscale.

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/deploy.sh` | **Deploy VM** - prompts for 1Password token, deploys infrastructure |
| `scripts/dp.sh` | **DevPod wrapper** - run on VM to manage devpods |
| `scripts/ssh-connect.sh` | SSH into the VM |
| `scripts/start-vm.sh` | Start a deallocated VM |
| `scripts/stop-vm.sh` | Stop and deallocate VM (saves compute costs) |
| `scripts/setup-vm.sh` | Setup VM with 1Password token (interactive prompt) |

## DevPod Integration

[DevPod](https://devpod.sh) lets you run devcontainers on your remote VM while developing locally. Think "GitHub Codespaces, but self-hosted and open-source."

### Quick Install

```bash
# From Azure Cloud Shell or local machine with az CLI
git clone https://github.com/kirderfg/dev_env.git
cd dev_env
./scripts/deploy.sh
```

Then SSH to the VM and run setup - see [Getting Started](#getting-started) above.

### How It Works

```
┌─────────────────┐                      ┌─────────────────────────────────┐
│  Azure Cloud    │   Azure API (deploy) │           Azure VM              │
│  Shell / Local  │─────────────────────►│                                 │
│                 │                      │  - DevPod CLI (dp.sh)           │
│  - Deploy VM    │                      │  - Docker                       │
│                 │                      │  - dev_env repo                 │
└─────────────────┘                      │  - Tailscale (auto-connected)   │
                                         │                                 │
┌─────────────────┐      Tailscale SSH   │  ┌───────────────────────────┐  │
│  Your Laptop    │◄────────────────────►│  │    DevPod Container       │  │
│  (Tailscale)    │   (no public SSH!)   │  │  ┌─────────────────────┐  │  │
│                 │                      │  │  │ Your Project        │  │  │
│  VS Code /      │      Tailscale SSH   │  │  │ + Dev Tools         │  │  │
│  Terminal       │◄────────────────────►│  │  │ + Tailscale SSH     │  │  │
└─────────────────┘                      │  │  └─────────────────────┘  │  │
                                         │  └───────────────────────────┘  │
                                         └─────────────────────────────────┘

NSG: All inbound traffic DENIED (Tailscale uses outbound connections only)
```

DevPods are managed **on the VM** using `~/dev_env/scripts/dp.sh`. Each devpod container gets its own Tailscale IP for direct SSH access.

### Prerequisites

**Azure CLI** - [Install instructions](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

Everything else is installed automatically by `./scripts/deploy.sh`.

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
# Deploy the VM
./scripts/deploy.sh

# SSH in and setup
ssh azureuser@dev-vm
git clone https://github.com/kirderfg/dev_env.git ~/dev_env
~/dev_env/scripts/setup-vm.sh
```

**What it does:**
1. Deploys Azure VM with Tailscale
2. Installs DevPod, Docker, shell-bootstrap tools
3. Configures gh, atuin, and other tools via 1Password

### Usage

All devpod commands run **on the VM**, not locally. SSH to the VM first.

#### Create a DevPod Workspace

```bash
# SSH to the VM
./scripts/ssh-connect.sh

# On the VM: create workspace from GitHub repo
~/dev_env/scripts/dp.sh up https://github.com/your/repo

# SSH into the devpod container
~/dev_env/scripts/dp.sh ssh your-repo
```

**Full example session:**
```bash
$ ./scripts/ssh-connect.sh
azureuser@vm-dev:~$ ~/dev_env/scripts/dp.sh up https://github.com/microsoft/vscode-remote-try-go
# ... builds container ...

azureuser@vm-dev:~$ ~/dev_env/scripts/dp.sh ssh vscode-remote-try-go
vscode@devcontainer:/workspaces/vscode-remote-try-go$ go run server.go
```

#### Connect via Tailscale (Recommended)

Each devpod gets a Tailscale IP. Connect directly from anywhere:

```bash
# Find the devpod's Tailscale IP (named devpod-<workspace>)
ssh root@devpod-myproject
su - vscode
dev  # load shell environment
```

#### Manage Workspaces (on VM)

```bash
# List all workspaces
~/dev_env/scripts/dp.sh list

# SSH into existing workspace
~/dev_env/scripts/dp.sh ssh my-workspace

# Rebuild workspace (recreate container)
~/dev_env/scripts/dp.sh rebuild my-workspace

# Delete workspace completely
~/dev_env/scripts/dp.sh delete my-workspace
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

## After |

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
│  │  setup-vm.sh        │                │  --workspace-env passes      │   │
│  │  prompts for token  │                │  OP_SERVICE_ACCOUNT_TOKEN    │   │
│  │  saves to:          │                │  to container environment    │   │
│  │  ~/.config/dev_env/ │                │                              │   │
│  │  op_token           │                │  shell-bootstrap picks up    │   │
│  │                     │                │  token from env var and      │   │
│  │  Token persists on  │                │  configures everything       │   │
│  │  VM disk (survives  │                │                              │   │
│  │  restarts)          │                │                              │   │
│  └─────────────────────┘                └──────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### For Azure VM

After deploying the VM, SSH in and run the setup script:

```bash
ssh azureuser@dev-vm
git clone https://github.com/kirderfg/dev_env.git ~/dev_env
~/dev_env/scripts/setup-vm.sh
```

The script prompts for your token (input is hidden). The token is saved to the VM and persists across restarts.

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

- **No public SSH access** - All inbound traffic blocked by NSG
- **Tailscale-only access** - VM auto-connects to Tailscale on boot
- SSH key authentication only (no passwords)
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
│   ├── setup-vm.sh             # Setup VM with 1Password token
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
