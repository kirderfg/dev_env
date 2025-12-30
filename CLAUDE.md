# Dev Environment - Claude Instructions

## Architecture

DevPods run on an Azure VM (dev-vm). All devpod management commands are executed **on the VM**, not locally.

**Network Security**: The VM has **no public SSH access** - all inbound traffic is blocked by NSG. Access is via **Tailscale only**. The VM auto-connects to Tailscale during cloud-init as hostname `dev-vm`.

### Initial VM Setup (Azure Cloud Shell - Recommended)

The safest way to deploy is from Azure Cloud Shell - no local dependencies needed.

**Step 1: Open Azure Cloud Shell**
1. Go to [portal.azure.com](https://portal.azure.com)
2. Click the Cloud Shell icon (>_) in the top navigation bar
3. Select **Bash** if prompted for shell type
4. Wait for the shell to initialize

**Step 2: Deploy the VM**
```bash
# Set your 1Password Service Account Token
export OP_SERVICE_ACCOUNT_TOKEN='ops_eyJ...'

# Run the bootstrap script (one-liner)
curl -fsSL https://raw.githubusercontent.com/kirderfg/dev_env/main/scripts/bootstrap.sh | bash
```

**What the bootstrap script does:**
1. Installs 1Password CLI and GitHub CLI
2. Authenticates with GitHub using PAT from 1Password
3. Clones the dev_env repo
4. Fetches SSH key from 1Password (`op://DEV_CLI/dev-vm-key`)
5. Fetches Tailscale auth key from 1Password (`op://DEV_CLI/Tailscale/auth_key`)
6. Deploys the Azure VM with Tailscale auto-connect enabled
7. Waits for VM to connect to Tailscale, then syncs secrets and clones dev_env

### Alternative: Local Machine Setup
If you prefer to run from a local machine with az CLI:
```bash
./setup.sh
```

This creates the VM with:
- Docker and DevPod CLI pre-installed
- 1Password CLI for secrets
- GitHub CLI configured via 1Password PAT
- The `dev_env` repo cloned to `~/dev_env`

## DevPod Deployment

**SSH to the VM via Tailscale first**, then use the `dp` wrapper script - never use `devpod` directly.

```bash
# Connect to VM via Tailscale (no public SSH access)
ssh azureuser@dev-vm
```

### Deploy a new workspace (on VM)
```bash
~/dev_env/scripts/dp.sh up https://github.com/user/repo
```

### Rebuild an existing workspace
```bash
~/dev_env/scripts/dp.sh rebuild workspace-name
```

### Delete and redeploy (full reset)
```bash
~/dev_env/scripts/dp.sh delete workspace-name
~/dev_env/scripts/dp.sh up https://github.com/user/repo
```

### Other commands
```bash
~/dev_env/scripts/dp.sh list        # List workspaces
~/dev_env/scripts/dp.sh ssh <ws>    # SSH into workspace
~/dev_env/scripts/dp.sh delete <ws> # Delete workspace
```

The `dp` script automatically:
- Injects `OP_SERVICE_ACCOUNT_TOKEN` from `~/.config/dev_env/op_token`
- Sets `SHELL_BOOTSTRAP_NONINTERACTIVE=1`
- Uses the local `docker` provider

## DevContainer Template

Projects should use the shared template via **git submodule** (preferred) or copy files directly.

### Option 1: Git Submodule (Preferred)
```bash
cd /path/to/project
git submodule add https://github.com/kirderfg/devcontainer-template.git .devcontainer
git commit -m "Add devcontainer template as submodule"
git push
```

To update the template in a project:
```bash
git submodule update --remote .devcontainer
git commit -m "Update devcontainer template"
```

### Option 2: Copy files directly
```bash
cp ~/dev_env/templates/devcontainer/*.sh /path/to/project/.devcontainer/
cp ~/dev_env/templates/devcontainer/devcontainer.json /path/to/project/.devcontainer/
```

### What the template provides
- **Python 3.12 + Node 20** base image
- **1Password CLI** for secret management
- **Tailscale SSH** for remote access (auto-removes old devices on redeploy)
- **Shell-bootstrap** for terminal tools (zsh, starship, atuin, yazi, pet, etc.)
- **Docker-in-Docker** for container operations
- **Pre-commit hooks** framework
- **Git + GitHub CLI** configuration

## Important: Container Users

### Template uses `vscode` user
The template uses Python image which has `vscode` as the default user (uid 1000).
- `remoteUser: "vscode"` in devcontainer.json
- Shell-bootstrap installs to `/home/vscode/`
- The `dev` alias and all tools work for `vscode` user

### Tailscale SSH logs in as `root`
When you SSH via Tailscale (`ssh root@<tailscale-ip>`), you're logged in as root.
To use the full shell setup with `dev` alias:
```bash
ssh root@<tailscale-ip>
su - vscode
dev
```

### Common mistake: Wrong user
If `dev` alias doesn't work, you're probably logged in as wrong user:
- Check with `whoami`
- Switch to vscode: `su - vscode`
- Then run `dev`

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
| `op://DEV_CLI/dev-vm-key/private key` | SSH private key for VM access | Yes |
| `op://DEV_CLI/dev-vm-key/public key` | SSH public key for VM access | Yes |
| `op://DEV_CLI/GitHub/PAT` | GitHub Personal Access Token (for cloning dev_env) | Yes |
| `op://DEV_CLI/Tailscale/auth_key` | Tailscale auth key for device registration | Yes |
| `op://DEV_CLI/Tailscale/api_key` | Tailscale API key for removing old devices | Yes |
| `op://DEV_CLI/Atuin/username` | Atuin shell history sync | Optional |
| `op://DEV_CLI/Atuin/password` | Atuin shell history sync | Optional |
| `op://DEV_CLI/Atuin/key` | Atuin shell history sync | Optional |

## Key Paths

**On your local machine:**
| Path | Purpose |
|------|---------|
| `~/.config/dev_env/op_token` | 1Password Service Account token (synced to VM) |
| `~/dev_env/setup.sh` | Initial VM deployment script |

**SSH access**: `ssh azureuser@dev-vm` (via Tailscale, no public IP)

**On the VM (dev-vm):**
| Path | Purpose |
|------|---------|
| `~/.config/dev_env/op_token` | 1Password Service Account token |
| `~/dev_env/scripts/dp.sh` | DevPod wrapper script |
| `~/dev_env/templates/devcontainer/` | Devcontainer template files |

**Inside devpod containers:**
| Path | Purpose |
|------|---------|
| `/tmp/tailscaled.log` | Tailscale daemon logs |

## Common Mistakes to Avoid

### 1. Using `devpod` directly
Always use `~/dev_env/scripts/dp.sh` - it injects the 1Password token.

### 2. Modifying devcontainer files without updating template
If you fix something in a project's devcontainer, also update the template in `dev_env/templates/devcontainer/`.

### 3. Forgetting to delete cached images on rebuild
If `--recreate` doesn't pick up devcontainer.json changes (like new base image):
```bash
~/dev_env/scripts/dp.sh delete workspace-name
docker image prune -f
~/dev_env/scripts/dp.sh up https://github.com/user/repo
```

### 4. Port forwarding issues
Port forwarding is disabled in the template. Access services via Tailscale IP directly.

### 5. Not redirecting tailscaled output
Always redirect tailscaled to a log file to prevent hanging:
```bash
sudo tailscaled --state=... --socket=... > /tmp/tailscaled.log 2>&1 &
```

## Troubleshooting

### DevPod appears to hang during deployment
- Check if Tailscale daemon output is redirected
- Look at `/tmp/tailscaled.log` inside container
- The deployment may have completed - check `devpod list`

### `dev` alias not found
- You're logged in as wrong user (root instead of vscode)
- Run `su - vscode` then `dev`

### Tailscale device already exists
- The template auto-removes old devices if API key is configured
- Check 1Password for `op://DEV_CLI/Tailscale/api_key`

### Shell-bootstrap didn't install properly
- Check if `~/.config/shell-bootstrap/zshrc` exists
- Check if block was added to `~/.zshrc`: `grep shell-bootstrap ~/.zshrc`
- Re-run: `curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh | bash`
