#!/bin/bash
# Install all shell tools on the VM
# This script installs tools but does NOT configure them with secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="install-tools"
source "$SCRIPT_DIR/../core/common.sh"

log "Starting VM tool installation..."

# Install apt packages
install_apt_packages() {
    log "Installing apt packages..."
    sudo apt-get update
    sudo apt-get install -y \
        zsh \
        git \
        curl \
        jq \
        unzip \
        tmux \
        htop \
        fzf \
        ripgrep \
        fd-find \
        bat
}

# Install 1Password CLI
install_1password_cli() {
    if command -v op &> /dev/null; then
        log "1Password CLI already installed ($(op --version))"
        return 0
    fi

    log "Installing 1Password CLI..."
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | \
        sudo tee /etc/apt/sources.list.d/1password.list
    sudo apt-get update
    sudo apt-get install -y 1password-cli
    log "1Password CLI installed"
}

# Install Node.js 20.x
install_nodejs() {
    if command -v node &> /dev/null; then
        log "Node.js already installed ($(node --version))"
        return 0
    fi

    log "Installing Node.js 20.x..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    log "Node.js $(node --version) installed"
}

# Install Starship prompt
install_starship() {
    if command -v starship &> /dev/null; then
        log "Starship already installed ($(starship --version))"
        return 0
    fi

    log "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    log "Starship installed"
}

# Install Atuin shell history
install_atuin() {
    if command -v atuin &> /dev/null; then
        log "Atuin already installed ($(atuin --version))"
        return 0
    fi

    log "Installing Atuin..."
    curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | bash -s -- -y 2>/dev/null || {
        warn "Atuin installation script failed, trying cargo..."
        if command -v cargo &> /dev/null; then
            cargo install atuin
        else
            warn "cargo not available, skipping Atuin"
            return 0
        fi
    }
    log "Atuin installed"
}

# Install Delta git diff viewer
install_delta() {
    if command -v delta &> /dev/null; then
        log "Delta already installed ($(delta --version | head -1))"
        return 0
    fi

    log "Installing Delta git diff viewer..."
    local version="0.16.5"
    curl -sL "https://github.com/dandavison/delta/releases/download/${version}/delta-${version}-x86_64-unknown-linux-gnu.tar.gz" | \
        tar xz -C /tmp
    sudo mv "/tmp/delta-${version}-x86_64-unknown-linux-gnu/delta" /usr/local/bin/
    rm -rf "/tmp/delta-${version}-x86_64-unknown-linux-gnu"
    log "Delta installed"
}

# Install Pet snippets manager
install_pet() {
    if command -v pet &> /dev/null; then
        log "Pet already installed ($(pet version))"
        return 0
    fi

    log "Installing Pet snippets manager..."
    local version="0.8.2"
    curl -sL "https://github.com/knqyf263/pet/releases/download/v${version}/pet_${version}_linux_amd64.tar.gz" | \
        tar xz -C /tmp
    sudo mv /tmp/pet /usr/local/bin/
    log "Pet installed"
}

# Install Claude Code CLI
install_claude_code() {
    if command -v claude &> /dev/null; then
        log "Claude Code CLI already installed"
        return 0
    fi

    log "Installing Claude Code CLI..."
    sudo npm install -g @anthropic-ai/claude-code
    log "Claude Code CLI installed"
}

# Install Task Master
install_task_master() {
    if command -v task-master &> /dev/null; then
        log "Task Master already installed"
        return 0
    fi

    log "Installing Task Master..."
    sudo npm install -g task-master-ai
    log "Task Master installed"
}

# Install DevPod
install_devpod() {
    if command -v devpod &> /dev/null; then
        log "DevPod already installed ($(devpod version))"
        return 0
    fi

    log "Installing DevPod..."
    curl -L -o /tmp/devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
    sudo install -c -m 0755 /tmp/devpod /usr/local/bin
    rm -f /tmp/devpod
    log "DevPod installed"
}

# Install Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log "Docker already installed ($(docker --version))"
        return 0
    fi

    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    log "Docker installed (you may need to log out and back in for group changes)"
}

# Main installation
main() {
    install_apt_packages
    install_1password_cli
    install_nodejs
    install_starship
    install_atuin
    install_delta
    install_pet
    install_claude_code
    install_task_master
    install_devpod
    install_docker

    log "All tools installed successfully"
    info "Run scripts/vm/configure-tools.sh to configure tools with secrets"
}

main "$@"
