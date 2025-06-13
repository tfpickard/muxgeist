#!/bin/bash

# Muxgeist Installation Script
# Sets up the complete Muxgeist system

set -e

# Configuration
INSTALL_DIR="${MUXGEIST_INSTALL_DIR:-$HOME/.local/bin}"
TMUX_CONFIG="$HOME/.tmux.conf"
BACKUP_SUFFIX=".muxgeist-backup-$(date +%Y%m%d-%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║              🌟 MUXGEIST INSTALLER           ║"
    echo "║        AI-Powered Terminal Assistant         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_step() {
    echo -e "${YELLOW}▶${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_dependencies() {
    log_step "Checking dependencies..."

    local missing_deps=()

    # Check tmux
    if ! command -v tmux &>/dev/null; then
        missing_deps+=("tmux")
    fi

    # Check Python 3
    if ! command -v python3 &>/dev/null; then
        missing_deps+=("python3")
    fi

    # Check make/gcc for daemon
    if ! command -v make &>/dev/null; then
        missing_deps+=("make")
    fi

    if ! command -v gcc &>/dev/null; then
        missing_deps+=("gcc")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Install them with:"
        echo "  macOS: brew install tmux python3"
        echo "  Linux: sudo apt install tmux python3 build-essential"
        echo "         or: sudo paru -S tmux python3 base-devel"
        exit 1
    fi

    log_success "All dependencies found"
}

build_daemon() {
    log_step "Building Muxgeist daemon..."

    if [ ! -f "Makefile" ]; then
        log_error "Makefile not found - run from Muxgeist source directory"
        exit 1
    fi

    make clean
    make

    log_success "Daemon built successfully"
}

setup_python_env() {
    log_step "Setting up Python environment..."

    # Check if requirements.txt exists
    if [ ! -f "requirements.txt" ]; then
        log_error "requirements.txt not found"
        exit 1
    fi

    # Install Python dependencies
    if command -v pip3 &>/dev/null; then
        pip3 install -r requirements.txt
    else
        python3 -m pip install -r requirements.txt
    fi

    log_success "Python dependencies installed"
}

install_binaries() {
    log_step "Installing Muxgeist binaries..."

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Install daemon and client
    install -m 755 muxgeist-daemon "$INSTALL_DIR/"
    install -m 755 muxgeist-client "$INSTALL_DIR/"

    # Install Python scripts
    install -m 755 muxgeist_ai.py "$INSTALL_DIR/"
    install -m 755 muxgeist-interactive.py "$INSTALL_DIR/"

    # Install tmux scripts
    install -m 755 muxgeist-summon "$INSTALL_DIR/"
    install -m 755 muxgeist-dismiss "$INSTALL_DIR/"

    log_success "Binaries installed to $INSTALL_DIR"
}

setup_tmux_config() {
    log_step "Setting up tmux configuration..."

    # Backup existing tmux config if it exists
    if [ -f "$TMUX_CONFIG" ]; then
        cp "$TMUX_CONFIG" "${TMUX_CONFIG}${BACKUP_SUFFIX}"
        log_info "Backed up existing tmux config to ${TMUX_CONFIG}${BACKUP_SUFFIX}"
    fi

    # Check if our config is already included
    if grep -q "muxgeist" "$TMUX_CONFIG" 2>/dev/null; then
        log_info "Muxgeist configuration already present in tmux config"
    else
        # Append our configuration
        echo "" >>"$TMUX_CONFIG"
        echo "# Muxgeist Configuration" >>"$TMUX_CONFIG"
        cat muxgeist.tmux.conf >>"$TMUX_CONFIG"
        log_success "Added Muxgeist configuration to tmux config"
    fi
}

setup_systemd_service() {
    log_step "Setting up Muxgeist daemon service (optional)..."

    if command -v systemctl &>/dev/null; then
        local service_dir="$HOME/.config/systemd/user"
        mkdir -p "$service_dir"

        cat >"$service_dir/muxgeist.service" <<EOF
[Unit]
Description=Muxgeist AI Terminal Assistant Daemon
After=default.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/muxgeist-daemon
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

        # Enable and start the service
        systemctl --user daemon-reload
        systemctl --user enable muxgeist.service

        log_success "Systemd service created (not started yet)"
        log_info "Start with: systemctl --user start muxgeist"
    else
        log_info "Systemd not available - daemon must be started manually"
    fi
}

update_path() {
    log_step "Updating PATH..."

    # Check if install dir is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        # Add to shell rc files
        local shell_rc=""
        case "$SHELL" in
        */zsh) shell_rc="$HOME/.zshrc" ;;
        */bash) shell_rc="$HOME/.bashrc" ;;
        *) shell_rc="$HOME/.profile" ;;
        esac

        if [ -w "$shell_rc" ]; then
            echo "" >>"$shell_rc"
            echo "# Muxgeist PATH" >>"$shell_rc"
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >>"$shell_rc"
            log_success "Added $INSTALL_DIR to PATH in $shell_rc"
            log_info "Restart your shell or run: source $shell_rc"
        else
            log_info "Add $INSTALL_DIR to your PATH manually"
        fi
    else
        log_success "Install directory already in PATH"
    fi
}

create_env_template() {
    log_step "Creating environment template..."

    if [ ! -f "$HOME/.muxgeist.env" ]; then
        cat >"$HOME/.muxgeist.env" <<'EOF'
# Muxgeist Environment Configuration
# Source this file or add to your shell rc

# AI Provider API Keys (set at least one)
# export ANTHROPIC_API_KEY="your-anthropic-key-here"
# export OPENAI_API_KEY="your-openai-key-here" 
# export OPENROUTER_API_KEY="your-openrouter-key-here"

# Optional: Default provider
# export MUXGEIST_AI_PROVIDER="anthropic"

# Optional: OpenRouter model override
# export OPENROUTER_MODEL="anthropic/claude-3.5-sonnet"

# Optional: Install directory (if non-standard)
# export MUXGEIST_INSTALL_DIR="$HOME/.local/bin"
EOF
        log_success "Created environment template at $HOME/.muxgeist.env"
        log_info "Edit this file to configure your AI API keys"
    else
        log_info "Environment file already exists at $HOME/.muxgeist.env"
    fi
}

run_tests() {
    log_step "Running installation tests..."

    # Test daemon compilation
    if [ -x "./muxgeist-daemon" ]; then
        log_success "Daemon executable created"
    else
        log_error "Daemon compilation failed"
        return 1
    fi

    # Test Python imports
    if python3 -c "import sys; sys.path.insert(0, '.'); from muxgeist_ai import MuxgeistAI" 2>/dev/null; then
        log_success "Python AI service imports correctly"
    else
        log_error "Python AI service import failed"
        return 1
    fi

    # Test tmux scripts
    if [ -x "$INSTALL_DIR/muxgeist-summon" ]; then
        log_success "Tmux integration scripts installed"
    else
        log_error "Tmux scripts not found"
        return 1
    fi

    log_success "All tests passed"
}

print_next_steps() {
    echo ""
    echo -e "${BOLD}🎉 Muxgeist Installation Complete!${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo ""
    echo "1. 🔑 Configure API keys:"
    echo "   edit ~/.muxgeist.env"
    echo "   source ~/.muxgeist.env"
    echo ""
    echo "2. 🚀 Start the daemon:"
    echo "   muxgeist-daemon &"
    echo "   # or with systemd: systemctl --user start muxgeist"
    echo ""
    echo "3. 🌟 Launch tmux and summon Muxgeist:"
    echo "   tmux"
    echo "   Ctrl+G  (or prefix + g)"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "   Ctrl+G        - Summon/dismiss Muxgeist"
    echo "   muxgeist-summon --help  - See all options"
    echo "   python3 muxgeist_ai.py --providers  - Check API keys"
    echo ""
    echo -e "${BLUE}Happy terminal AI assistance! 🌟${NC}"
}

main() {
    print_header

    # Check if we're in the right directory
    if [ ! -f "muxgeist-daemon.c" ] || [ ! -f "muxgeist_ai.py" ]; then
        log_error "Please run from the Muxgeist source directory"
        exit 1
    fi

    # Installation steps
    check_dependencies
    build_daemon
    setup_python_env
    install_binaries
    setup_tmux_config
    update_path
    create_env_template

    # Optional systemd setup
    if [ "${1:-}" != "--no-systemd" ]; then
        setup_systemd_service
    fi

    # Test installation
    run_tests

    # Show next steps
    print_next_steps
}

# Handle command line arguments
case "${1:-}" in
--help | -h)
    echo "Muxgeist Installation Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --no-systemd    Skip systemd service setup"
    echo "  --help          Show this help"
    echo ""
    echo "Environment variables:"
    echo "  MUXGEIST_INSTALL_DIR    Installation directory (default: ~/.local/bin)"
    ;;
*)
    main "$@"
    ;;
esac
