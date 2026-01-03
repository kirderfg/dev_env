# Azure Cloud Shell Helpers
# Sourced by .bashrc after running setup-cloudshell.sh

# Aliases for dev_env scripts
alias deploy='~/clouddrive/dev_env/scripts/deploy.sh'
alias start-vm='~/clouddrive/dev_env/scripts/start-vm.sh'
alias stop-vm='~/clouddrive/dev_env/scripts/stop-vm.sh'
alias ssh-vm='ssh azureuser@dev-vm'

# Quick check if tools are available
cloudshell-status() {
    echo "=== Cloud Shell Dev Environment Status ==="
    echo ""

    # Check 1Password CLI
    if command -v op &> /dev/null; then
        echo "1Password CLI: $(op --version 2>/dev/null || echo 'installed')"
    else
        echo "1Password CLI: NOT INSTALLED"
    fi

    # Check Claude CLI
    if command -v claude &> /dev/null; then
        echo "Claude Code CLI: $(claude --version 2>/dev/null | head -1 || echo 'installed')"
    else
        echo "Claude Code CLI: NOT INSTALLED"
    fi

    # Check npm
    echo "npm: $(npm --version 2>/dev/null || echo 'not found')"
    echo "npm prefix: $(npm config get prefix 2>/dev/null || echo 'not set')"

    # Check node
    echo "Node.js: $(node --version 2>/dev/null || echo 'not found')"

    # Check dev_env
    if [ -d ~/clouddrive/dev_env ]; then
        echo "dev_env: ~/clouddrive/dev_env (installed)"
    else
        echo "dev_env: NOT INSTALLED"
    fi

    # Check Azure login
    if az account show &>/dev/null 2>&1; then
        ACCOUNT=$(az account show --query name -o tsv 2>/dev/null)
        echo "Azure: logged in ($ACCOUNT)"
    else
        echo "Azure: not logged in"
    fi

    echo ""
}

# Re-run bootstrap to update tools
cloudshell-update() {
    echo "Updating Cloud Shell dev environment..."
    if [ -f ~/clouddrive/dev_env/scripts/setup-cloudshell.sh ]; then
        bash ~/clouddrive/dev_env/scripts/setup-cloudshell.sh
    else
        curl -fsSL https://raw.githubusercontent.com/kirderfg/dev_env/main/scripts/setup-cloudshell.sh | bash
    fi
}

# Help text
cloudshell-help() {
    echo "=== Cloud Shell Dev Environment Commands ==="
    echo ""
    echo "Status & Setup:"
    echo "  cloudshell-status  - Show installed tools and status"
    echo "  cloudshell-update  - Update/reinstall all tools"
    echo ""
    echo "VM Management:"
    echo "  deploy             - Deploy new VM (runs deploy.sh)"
    echo "  start-vm           - Start the VM"
    echo "  stop-vm            - Stop the VM (deallocate)"
    echo "  ssh-vm             - SSH to dev-vm via Tailscale"
    echo ""
    echo "Installed Tools:"
    echo "  op                 - 1Password CLI"
    echo "  claude             - Claude Code CLI"
    echo "  az                 - Azure CLI (built-in)"
    echo ""
}
