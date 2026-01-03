# Dev Environment - Claude Instructions

## Architecture

DevPods run on an Azure VM (dev-vm). All devpod management commands are executed **on the VM**, not locally.

**Network Security**: The VM has **no public SSH access** - all inbound traffic is blocked by NSG. Access is via **Tailscale only**. The VM auto-connects to Tailscale during cloud-init as hostname `dev-vm`.

### Initial VM Setup (Azure Cloud Shell)

**Step 0: Bootstrap Cloud Shell (first time only)**

Azure Cloud Shell resets most files between sessions. Run this bootstrap once to install persistent tools:
```bash
git clone https://github.com/kirderfg/dev_env.git ~/clouddrive/dev_env && ~/clouddrive/dev_env/scripts/cloudshell/setup.sh
source ~/.bashrc
```

This installs to `~/clouddrive` (persistent) and configures:
- 1Password CLI (`op`)
- Claude Code CLI (`claude`)
- npm with persistent global packages
- dev_env repository

After bootstrap, you can use `cloudshell-status` to check installed tools.

**Step 1: Deploy the VM from Cloud Shell**
```bash
cd ~/clouddrive/dev_env
./scripts/azure/deploy.sh
```

The deploy script will:
1. Prompt for your 1Password Service Account Token
2. Fetch Tailscale auth key from 1Password
3. Deploy the Azure VM with Tailscale auto-connect
4. Wait for cloud-init to complete

**Step 2: Setup the VM**

After the VM is ready, SSH in and run setup:
```bash
ssh azureuser@dev-vm
git clone https://github.com/kirderfg/dev_env.git ~/dev_env
~/dev_env/scripts/vm/setup.sh
```

The setup script will:
1. Prompt for your 1Password Service Account Token
2. Save the token for devpod to use
3. Run shell-bootstrap to configure gh, atuin, and other tools

## DevPod Deployment

**SSH to the VM via Tailscale first**, then use the `dp` wrapper script - never use `devpod` directly.

```bash
# Connect to VM via Tailscale (no public SSH access)
ssh azureuser@dev-vm
```

### Deploy a new workspace (on VM)
```bash
~/dev_env/scripts/devpod/dp.sh up https://github.com/user/repo
```

### Rebuild an existing workspace
```bash
~/dev_env/scripts/devpod/dp.sh rebuild workspace-name
```

### Delete and redeploy (full reset)
```bash
~/dev_env/scripts/devpod/dp.sh delete workspace-name
~/dev_env/scripts/devpod/dp.sh up https://github.com/user/repo
```

### Other commands
```bash
~/dev_env/scripts/devpod/dp.sh list        # List workspaces
~/dev_env/scripts/devpod/dp.sh ssh <ws>    # SSH into workspace
~/dev_env/scripts/devpod/dp.sh delete <ws> # Delete workspace
```

### Start/stop all workspaces
```bash
~/dev_env/scripts/devpod/start-all.sh   # Start all workspaces
~/dev_env/scripts/devpod/stop-all.sh    # Stop all workspaces
```

### Auto-start on VM reboot
DevPods are configured to auto-start when the VM boots via systemd:
```bash
# Check service status
sudo systemctl status devpod-autostart

# Manually restart all devpods
sudo systemctl restart devpod-autostart

# Disable auto-start
sudo systemctl disable devpod-autostart

# Re-enable auto-start (run setup script)
~/dev_env/scripts/devpod/setup-autostart.sh
```

**Note**: After VM reboot, Tailscale in each container may take 30-60 seconds to register and become reachable.

The `dp` script automatically:
- Reads secrets from 1Password and injects them as environment variables
- Does NOT pass `OP_SERVICE_ACCOUNT_TOKEN` to containers (secrets stay on VM)
- Sets `SHELL_BOOTSTRAP_NONINTERACTIVE=1` and `SHELL_BOOTSTRAP_SKIP_1PASSWORD=1`
- Defaults to `--ide none` (no browser VSCode); override with `--ide vscode` if needed
- Uses the local `docker` provider

## DevContainer Template

The devcontainer configuration is built into this repo at `devcontainer/`. Projects can copy this or reference it.

### What the template provides
- **Python 3.12 + Node 20** base image
- **Tailscale SSH** for remote access (auto-removes old devices on redeploy)
- **Claude Code CLI** - AI coding assistant in terminal
- **Task Master** - AI-powered task management via MCP
- **Shell tools** (zsh, starship, atuin, delta, pet)
- **Docker-in-Docker** for container operations
- **Pre-commit hooks** framework
- **Git + GitHub CLI** configuration

**Security Note**: DevPod containers do NOT have access to 1Password. Secrets are injected as environment variables by `dp.sh` on the VM.

## Task Master

Task Master is an AI-powered task management system integrated as an MCP server for Claude Code. It's available on both the VM and inside devpod containers.

### Usage
```bash
# Initialize Task Master in a project
task-master init --name="my-project" -y

# Parse a PRD to generate tasks
task-master parse-prd --input=docs/prd.md

# List all tasks
task-master list

# Get next recommended task
task-master next

# Update task status
task-master set-status <id> done

# Expand a task into subtasks
task-master expand --id=<id>
```

### Model Configuration
Task Master is configured to use Claude Code CLI (free, no API key needed):
```bash
# Check current model config
task-master models

# Set main model to use Claude Code CLI
task-master models --set-main sonnet --claude-code
```

### MCP Integration
Task Master tools are available in Claude Code via MCP. The config is at `~/.claude/.mcp.json`:
```json
{
  "mcpServers": {
    "taskmaster-ai": {
      "command": "npx",
      "args": ["-y", "--package=task-master-ai", "task-master-ai"]
    }
  }
}
```

After restarting Claude Code, use `/mcp` to see available Task Master tools.

## Important: Users at Each Layer

There are two different contexts with different users:

### 1. The VM (dev-vm)
- **User:** `azureuser`
- **Access:** `ssh azureuser@dev-vm` via Tailscale
- **Purpose:** Run devpod commands, manage containers
- **No `vscode` user here** - it only exists inside containers

### 2. Devpod Containers
- **Default user:** `vscode` (from Python devcontainer image, uid 1000)
- **Access via Tailscale SSH:** `ssh root@devpod-<workspace-name>`
- **Access via devpod:** `~/dev_env/scripts/devpod/dp.sh ssh <workspace-name>`
- Shell-bootstrap installs to `/home/vscode/`
- The `dev` alias and all tools work for `vscode` user

### Tailscale SSH into containers logs in as `root`
When you SSH via Tailscale to a container (`ssh root@devpod-<workspace>`), you're logged in as root.
To use the full shell setup with `dev` alias:
```bash
ssh root@devpod-<workspace-name>
su - vscode
dev
```

### Common mistake: Confusing VM and container
If `su - vscode` fails with "user does not exist":
- You're on the **VM**, not inside a container
- The VM user is `azureuser`, not `vscode`
- First SSH into a devpod container, then switch to vscode

## Tailscale Configuration

### How it works
1. onCreate.sh reads auth key from 1Password: `op://DEV_CLI/Tailscale/auth_key`
2. If API key exists (`op://DEV_CLI/Tailscale/api_key`), it removes any existing device with same hostname
3. Registers new device with hostname `devpod-<workspace-name>`
4. Enables Tailscale SSH for remote access

### Device naming
Devices are named `devpod-<workspace-name>`, e.g.:
- `devpod-shredder`
- `devpod-garmin`

### Tailscale logs
Tailscale daemon output is redirected to `/tmp/tailscaled.log` to prevent devpod from appearing to hang.

### Managing Tailscale devices
The template automatically cleans up old devices with the same name when redeploying.

To manually list/clean devices:
```bash
# List all devpod devices (run from inside a container)
source ~/.config/dev_env/init.sh
TAILSCALE_API_KEY=$(op read "op://DEV_CLI/Tailscale/api_key")
curl -s -H "Authorization: Bearer $TAILSCALE_API_KEY" \
  "https://api.tailscale.com/api/v2/tailnet/-/devices" | \
  jq -r '.devices[] | select(.name | startswith("devpod-")) | "\(.name) \(.id)"'

# Delete a specific device by ID
curl -s -X DELETE -H "Authorization: Bearer $TAILSCALE_API_KEY" \
  "https://api.tailscale.com/api/v2/device/<device-id>"
```

**Important**: The `api_key` in 1Password is required for automatic cleanup. Without it, Tailscale will append numbers (e.g., `devpod-shredder-1`, `devpod-shredder-2`) when devices already exist.

## 1Password Secrets Required

The devcontainer template reads these secrets from 1Password vault `DEV_CLI`:

| Secret Path | Purpose | Required |
|-------------|---------|----------|
| `op://DEV_CLI/GitHub/PAT` | GitHub Personal Access Token (for cloning dev_env) | Yes |
| `op://DEV_CLI/Tailscale/auth_key` | Tailscale auth key for device registration | Yes |
| `op://DEV_CLI/Tailscale/api_key` | Tailscale API key for removing old devices | Yes |
| `op://DEV_CLI/Atuin/username` | Atuin shell history sync | Optional |
| `op://DEV_CLI/Atuin/password` | Atuin shell history sync | Optional |
| `op://DEV_CLI/Atuin/key` | Atuin shell history sync | Optional |

## Key Paths

**In Azure Cloud Shell (persistent in ~/clouddrive):**
| Path | Purpose |
|------|---------|
| `~/clouddrive/dev_env/` | dev_env repository (persistent) |
| `~/clouddrive/bin/op` | 1Password CLI (persistent) |
| `~/clouddrive/bin/claude` | Claude Code CLI wrapper (persistent) |
| `~/clouddrive/.npm-packages/` | npm packages for CLI tools (persistent) |

**Cloud Shell helper commands:**
| Command | Purpose |
|---------|---------|
| `cloudshell-status` | Show installed tools and status |
| `cloudshell-update` | Update/reinstall all tools |
| `cloudshell-help` | Show available commands |
| `deploy` | Alias for deploy.sh |
| `ssh-vm` | SSH to dev-vm via Tailscale |

**SSH access**: `ssh azureuser@dev-vm` (via Tailscale, no public IP)

**On the VM (dev-vm):**
| Path | Purpose |
|------|---------|
| `~/.config/dev_env/op_token` | 1Password Service Account token |
| `~/dev_env/scripts/devpod/dp.sh` | DevPod wrapper script |
| `~/dev_env/scripts/devpod/start-all.sh` | Start all workspaces |
| `~/dev_env/scripts/devpod/stop-all.sh` | Stop all workspaces |
| `~/dev_env/scripts/devpod/setup-autostart.sh` | Install systemd auto-start service |
| `~/dev_env/scripts/vm/setup.sh` | VM setup script |
| `~/dev_env/scripts/azure/deploy.sh` | Azure VM deployment |

**Inside devpod containers:**
| Path | Purpose |
|------|---------|
| `/tmp/tailscaled.log` | Tailscale daemon logs |

## Common Mistakes to Avoid

### 1. Using `devpod` directly
Always use `~/dev_env/scripts/devpod/dp.sh` - it injects secrets as env vars.

### 2. Modifying devcontainer files without updating dev_env
If you fix something in a project's devcontainer, also update the template in the `devcontainer/` directory of this repo.

### 3. Forgetting to delete cached images on rebuild
If `--recreate` doesn't pick up devcontainer.json changes (like new base image):
```bash
~/dev_env/scripts/devpod/dp.sh delete workspace-name
docker image prune -f
~/dev_env/scripts/devpod/dp.sh up https://github.com/user/repo
```

### 4. Port forwarding issues
Port forwarding is disabled in the template. Access services via Tailscale IP directly.

### 5. Not redirecting tailscaled output
Always redirect tailscaled to a log file to prevent hanging:
```bash
sudo tailscaled --state=... --socket=... > /tmp/tailscaled.log 2>&1 &
```

## Troubleshooting

### Azure Cloud Shell: `op` or `claude` not found after restart
Azure Cloud Shell resets most files between sessions. Only `~/clouddrive` persists.
- Run the bootstrap script: `bash ~/clouddrive/dev_env/scripts/cloudshell/setup.sh`
- Or source bashrc: `source ~/.bashrc` (if already bootstrapped)
- Check status: `cloudshell-status`

### Azure Cloud Shell: npm packages or Claude CLI not working
Azure Files (backing ~/clouddrive) doesn't support symlinks. The bootstrap script installs npm packages locally and creates wrapper scripts.
- Re-run bootstrap: `cloudshell-update`
- Check Claude wrapper exists: `ls -la ~/clouddrive/bin/claude`
- Verify package installed: `ls ~/clouddrive/.npm-packages/claude-code/node_modules/@anthropic-ai/claude-code`

### DevPod appears to hang during deployment
- Check if Tailscale daemon output is redirected
- Look at `/tmp/tailscaled.log` inside container
- The deployment may have completed - check `devpod list`

### `dev` alias not found
- You're logged in as wrong user (root instead of vscode)
- Run `su - vscode` then `dev`

### `su: user vscode does not exist`
- You're on the **VM**, not inside a devpod container
- The `vscode` user only exists inside devpod containers
- To enter a container: `~/dev_env/scripts/devpod/dp.sh ssh <workspace-name>`
- Or via Tailscale: `ssh root@devpod-<workspace-name>`

### Tailscale device already exists
- The template auto-removes old devices if API key is configured
- Check 1Password for `op://DEV_CLI/Tailscale/api_key`

### Shell-bootstrap didn't install properly
- Check if `~/.config/shell-bootstrap/zshrc` exists
- Check if block was added to `~/.zshrc`: `grep shell-bootstrap ~/.zshrc`
- Re-run: `curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh | bash`

### gh/atuin not authenticated on VM
Run the configure script on the VM:
```bash
ssh azureuser@dev-vm
~/dev_env/scripts/vm/setup.sh
```

This will prompt for your 1Password token and configure tools via 1Password.
