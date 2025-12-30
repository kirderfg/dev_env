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
| `dev-vm-key` | SSH Key | `private key`, `public key` | VM SSH access |
| `GitHub` | Login | `PAT` | Clone private repos |
| `Tailscale` | Login | `auth_key`, `api_key` | Container networking |

### Create Service Account Token

1. Go to [1Password.com](https://1password.com) → Settings → Developer → Service Accounts
2. Create a new Service Account
3. Grant access to the `DEV_CLI` vault
4. Copy the token (starts with `ops_eyJ...`)

### Local WSL Setup (Windows) - SSH with 1Password Desktop

Use 1Password Desktop's SSH Agent for secure, biometric-authenticated SSH access.

**Step 1: Enable 1Password SSH Agent (Windows)**

1. Open 1Password Desktop app
2. Go to Settings → Developer
3. Enable **SSH Agent**
4. Enable **Use the SSH agent** for WSL

**Step 2: Configure WSL to use 1Password Agent**

```bash
# Add to ~/.bashrc or ~/.zshrc
export SSH_AUTH_SOCK=~/.1password/agent.sock
```

**Step 3: Configure SSH Host**

Add to `~/.ssh/config` (uses Tailscale hostname, not public IP):
```
Host dev-vm
    HostName dev-vm
    User azureuser
    IdentityAgent ~/.1password/agent.sock
```

**Step 4: Connect via Tailscale**

```bash
ssh dev-vm
# 1Password prompts for biometric/PIN authentication
# Connection goes through Tailscale (no public SSH port)
```

The SSH key never touches disk - 1Password handles it securely with biometric unlock.
The VM has no public SSH access - all connections go through Tailscale's encrypted mesh network.

### Alternative: Service Account Token (for automation)

For headless/automated scenarios without 1Password Desktop:

```bash
# Install 1Password CLI
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password-cli.list
sudo apt update && sudo apt install -y 1password-cli

# Save token and SSH on-demand
mkdir -p ~/.config/dev_env
echo 'ops_eyJ...' > ~/.config/dev_env/op_token
chmod 600 ~/.config/dev_env/op_token

# SSH using op read (key never saved to disk)
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/dev_env/op_token)"
ssh -i <(op read "op://DEV_CLI/dev-vm-key/private key") azureuser@<VM_IP>
```

## Quick Start (Azure Cloud Shell)

The easiest way to deploy - no local setup required:

**1. Open Azure Cloud Shell**
- Go to [portal.azure.com](https://portal.azure.com)
- Click the Cloud Shell icon (>_) in the top navigation bar
- Select **Bash** if prompted

**2. Deploy with one command**
```bash
export OP_SERVICE_ACCOUNT_TOKEN='ops_eyJ...'
curl -fsSL https://raw.githubusercontent.com/kirderfg/dev_env/main/scripts/bootstrap.sh | bash
```

**3. SSH to VM via Tailscale and start coding**
```bash
# From your laptop (VM auto-connected to Tailscale as 'dev-vm')
ssh azureuser@dev-vm

# On the VM - create a devpod
~/dev_env/scripts/dp.sh up https://github.com/your/repo
```

Note: The VM has no public SSH access. All connections go through Tailscale.

### Alternative: Local Machine Setup

If you have Azure CLI installed locally:

```bash
az login
./setup.sh
./scripts/ssh-connect.sh   # SSH into VM
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/bootstrap.sh` | **Azure Cloud Shell bootstrap** - installs tools, clones repo, deploys VM |
| `setup.sh` | Deploy VM (requires az CLI login) |
| `scripts/deploy.sh` | Deploy/update infrastructure, fetches SSH key from 1Password |
| `scripts/dp.sh` | **DevPod wrapper** - run on VM to manage devpods |
| `scripts/ssh-connect.sh` | SSH into the VM |
| `scripts/start-vm.sh` | Start a deallocated VM |
| `scripts/stop-vm.sh` | Stop and deallocate VM (saves compute costs) |
| `scripts/sync-secrets.sh` | Sync 1Password service account token to VM |

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
2. Deploys Azure VM (if not exists)
3. Adds SSH config entry `dev-vm`
4. Configures DevPod SSH provider

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
