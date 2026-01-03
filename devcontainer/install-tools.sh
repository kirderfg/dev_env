#!/bin/bash
# Install shell tools in container
# MINIMAL - NO 1Password CLI (secrets come from env vars)

set -e

echo "Installing shell tools..."

# Install Starship prompt
install_starship() {
    if command -v starship &> /dev/null; then
        echo "Starship already installed"
        return 0
    fi

    echo "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
}

# Install Atuin shell history
install_atuin() {
    if command -v atuin &> /dev/null; then
        echo "Atuin already installed"
        return 0
    fi

    echo "Installing Atuin..."
    curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | bash -s -- -y 2>/dev/null || {
        echo "Atuin installation script failed, trying cargo..."
        if command -v cargo &> /dev/null; then
            cargo install atuin
        else
            echo "cargo not available, skipping Atuin"
        fi
    }
}

# Install Delta git diff viewer
install_delta() {
    if command -v delta &> /dev/null; then
        echo "Delta already installed"
        return 0
    fi

    echo "Installing Delta..."
    local version="0.16.5"
    curl -sL "https://github.com/dandavison/delta/releases/download/${version}/delta-${version}-x86_64-unknown-linux-gnu.tar.gz" | \
        tar xz -C /tmp
    sudo mv "/tmp/delta-${version}-x86_64-unknown-linux-gnu/delta" /usr/local/bin/
    rm -rf "/tmp/delta-${version}-x86_64-unknown-linux-gnu"
}

# Install Pet snippets manager
install_pet() {
    if command -v pet &> /dev/null; then
        echo "Pet already installed"
        return 0
    fi

    echo "Installing Pet..."
    local version="0.8.2"
    curl -sL "https://github.com/knqyf263/pet/releases/download/v${version}/pet_${version}_linux_amd64.tar.gz" | \
        tar xz -C /tmp
    sudo mv /tmp/pet /usr/local/bin/
}

# Install Claude Code CLI
install_claude_code() {
    if command -v claude &> /dev/null; then
        echo "Claude Code CLI already installed"
        return 0
    fi

    echo "Installing Claude Code CLI..."
    npm install -g @anthropic-ai/claude-code
}

# Install Task Master
install_task_master() {
    if command -v task-master &> /dev/null; then
        echo "Task Master already installed"
        return 0
    fi

    echo "Installing Task Master..."
    npm install -g task-master-ai
}

# Run shell-bootstrap for shell configuration
install_shell_bootstrap() {
    if [[ -f "$HOME/.config/shell-bootstrap/zshrc" ]]; then
        echo "shell-bootstrap already installed"
        return 0
    fi

    echo "Installing shell-bootstrap..."
    curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/shell-bootstrap-install.sh
    SHELL_BOOTSTRAP_NONINTERACTIVE=1 SHELL_BOOTSTRAP_SKIP_1PASSWORD=1 bash /tmp/shell-bootstrap-install.sh
    rm -f /tmp/shell-bootstrap-install.sh
}

# Main installation
main() {
    install_starship
    install_atuin
    install_delta
    install_pet
    install_claude_code
    install_task_master
    install_shell_bootstrap

    echo "All tools installed"
}

main "$@"
