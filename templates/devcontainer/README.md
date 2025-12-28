# DevContainer Template for Python + Node Projects

A best-practices devcontainer configuration with security scanning, pre-commit hooks, and modern tooling.

## Stack

| Layer | Tool | Port |
|-------|------|------|
| API | FastAPI | 8000 |
| Frontend | Node/Vite | 3000 |
| Container | Docker-in-Docker | - |

## What's Included

### Languages & Runtimes
- Python 3.12 (Debian Bookworm)
- Node.js 20
- Docker-in-Docker with Compose v2

### Developer Tools (via shell-bootstrap)
- Zsh with vi-mode, Starship prompt
- Atuin (shell history sync)
- Yazi (file manager), Glow (markdown)
- Pet (snippets), Zoxide (smart cd)
- GitHub CLI (`gh`), Delta (git diff)
- Pre-commit hooks framework
- Black, Ruff, MyPy (Python)
- ESLint, Prettier (JavaScript)
- GitLens, Git Graph (VS Code)

### Security Tools
- **Gitleaks** - Secret detection in commits
- **Trivy** - Container/dependency vulnerability scanning
- **Bandit** - Python security linter
- **Safety** - Python dependency vulnerability checker
- **Hadolint** - Dockerfile linter
- **Snyk CLI** - Dependency & container scanning (run `snyk auth` to setup)
- **Snyk VS Code** - Real-time scanning in editor

## Quick Start

1. Copy template to your project:
   ```bash
   cp -r templates/devcontainer/.devcontainer your-project/
   cp templates/devcontainer/.pre-commit-config.yaml your-project/
   ```

2. Open in VS Code or DevPod:
   ```bash
   # VS Code
   code your-project/
   # Then: Ctrl+Shift+P -> "Dev Containers: Reopen in Container"

   # DevPod
   devpod up ./your-project --provider ssh --option HOST=dev-vm
   ```

3. First-time setup happens automatically via `onCreate.sh`

## Files

| File | Purpose |
|------|---------|
| `devcontainer.json` | Container configuration |
| `onCreate.sh` | One-time setup (installs tools, dependencies) |
| `postStart.sh` | Runs on every container start |
| `.pre-commit-config.yaml` | Git hooks configuration |
| `security-scan.sh` | Manual security scanning |

## Security Scanning

### Automatic (via pre-commit)
Every commit is automatically checked for:
- Secrets and API keys (gitleaks)
- Python security issues (bandit)
- Large files
- Merge conflicts

### Manual Scanning
```bash
# Quick scan (secrets + dependencies)
./security-scan.sh

# Full scan (includes container analysis)
./security-scan.sh full
```

### Snyk CLI
```bash
# Authenticate (one-time)
snyk auth

# Test dependencies
snyk test

# Test container image
snyk container test your-image:tag

# Monitor (adds to Snyk dashboard)
snyk monitor
```

### CI/CD Integration
Add to your GitHub Actions workflow:
```yaml
- name: Security Scan
  run: |
    pip install safety bandit
    safety check
    bandit -r src/

- name: Snyk Scan
  uses: snyk/actions/python@master
  env:
    SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}

- name: Container Scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: 'fs'
    scan-ref: '.'
```

## Pre-commit Hooks

Hooks run automatically on `git commit`:

| Hook | What it does |
|------|--------------|
| `trailing-whitespace` | Removes trailing spaces |
| `gitleaks` | Blocks commits with secrets |
| `black` | Formats Python code |
| `ruff` | Lints Python (fast) |
| `mypy` | Type checks Python |
| `bandit` | Security checks Python |
| `eslint` | Lints JavaScript |
| `prettier` | Formats JS/JSON/YAML |
| `hadolint` | Lints Dockerfiles |
| `commitizen` | Enforces commit message format |

### Commands
```bash
# Run all hooks on all files
pre-commit run --all-files

# Update hooks to latest versions
pre-commit autoupdate

# Skip hooks for emergency commit (not recommended)
git commit --no-verify -m "message"
```

## Customization

### Add Python Dependencies
Edit `pyproject.toml`:
```toml
[project.optional-dependencies]
dev = [
    "pytest",
    "black",
    "ruff",
    # add more...
]
```

### Add Ports
Edit `devcontainer.json`:
```json
"forwardPorts": [3000, 5000, 8000, 5432],
"portsAttributes": {
  "5432": { "label": "PostgreSQL" }
}
```

### Add VS Code Extensions
```json
"customizations": {
  "vscode": {
    "extensions": [
      "your.extension-id"
    ]
  }
}
```

## Troubleshooting

### Docker not working
Wait for Docker daemon to start, or run:
```bash
sudo dockerd &
```

### Pre-commit hooks slow
Skip specific hooks:
```bash
SKIP=mypy git commit -m "message"
```

### Snyk not working
Authenticate in VS Code:
1. Click Snyk icon in sidebar
2. Click "Connect VS Code with Snyk"
