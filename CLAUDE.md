# Dev Environment - Claude Instructions

## DevPod Deployment

**ALWAYS use the `dp` wrapper script to deploy devpods** - never use `devpod` directly.

### Deploy a new workspace
```bash
~/dev_env/scripts/dp.sh up https://github.com/user/repo
```

### Rebuild an existing workspace
```bash
~/dev_env/scripts/dp.sh rebuild workspace-name
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
- Uses the `ssh` provider with `HOST=dev-vm`

## DevContainer Template

When creating new project devcontainers, use the template from:
- `templates/devcontainer/devcontainer.json`
- `templates/devcontainer/onCreate.sh`
- `templates/devcontainer/postStart.sh`

The template includes:
- 1Password CLI installation and secret loading
- Tailscale for SSH access (reads auth key from 1Password)
- Shell-bootstrap for terminal tools (zsh, starship, atuin, etc.)
- Git configuration
- GitHub CLI authentication

## 1Password Secrets Required

The devcontainer template reads these secrets from 1Password:

| Secret Path | Purpose |
|-------------|---------|
| `op://DEV_CLI/Tailscale/auth_key` | Tailscale auth key for device registration |
| `op://DEV_CLI/Tailscale/api_key` | Tailscale API key for removing old devices (optional) |
| `op://DEV_CLI/Atuin/username` | Atuin shell history sync |
| `op://DEV_CLI/Atuin/password` | Atuin shell history sync |
| `op://DEV_CLI/Atuin/key` | Atuin shell history sync |
| `op://DEV_CLI/GitHub/PAT` | GitHub Personal Access Token |

## Key Paths

| Path | Purpose |
|------|---------|
| `~/.config/dev_env/op_token` | 1Password Service Account token |
| `~/dev_env/scripts/dp.sh` | DevPod wrapper script |
| `~/dev_env/templates/devcontainer/` | Devcontainer template files |
