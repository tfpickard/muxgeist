#!/bin/bash

# Complete Muxgeist Demo Script
# Demonstrates the full Muxgeist experience

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Demo configuration
DEMO_SESSION="muxgeist-demo"
DEMO_PROJECT_DIR="/tmp/muxgeist-demo-project"

print_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                        🌟 MUXGEIST DEMO 🌟                           ║"
    echo "║                   AI-Powered Terminal Assistant                       ║"
    echo "║                                                                       ║"
    echo "║  This demo will show you the complete Muxgeist experience:           ║"
    echo "║  • Context-aware AI analysis of your terminal sessions               ║"
    echo "║  • Smart suggestions based on your workflow                          ║"
    echo "║  • Seamless tmux integration with instant summoning                  ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_step() {
    echo -e "${YELLOW}▶${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

log_demo() {
    echo -e "${PURPLE}🎬${NC} $1"
}

wait_for_enter() {
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing=()
    
    # Check if we're already in tmux
    if [ -n "$TMUX" ]; then
        log_info "Already in tmux - good!"
    else
        log_info "Not in tmux - we'll create a demo session"
    fi
    
    # Check daemon
    if [ -x "./muxgeist-daemon" ]; then
        log_success "Daemon binary found"
    else
        log_info "Building daemon..."
        make clean && make
    fi
    
    # Check Python dependencies
    if python3 -c "from muxgeist_ai import MuxgeistAI" 2>/dev/null; then
        log_success "Python AI service ready"
    else
        log_info "Setting up Python dependencies..."
        pip3 install -r requirements.txt --user 2>/dev/null || true
    fi
    
    # Check scripts
    if [ -x "./muxgeist-summon" ]; then
        log_success "Tmux integration scripts found"
    else
        log_info "Making scripts executable..."
        chmod +x muxgeist-summon muxgeist-dismiss muxgeist-interactive.py
    fi
}

start_daemon() {
    log_step "Starting Muxgeist daemon..."
    
    # Kill any existing daemon
    pkill -f muxgeist-daemon 2>/dev/null || true
    sleep 1
    
    # Remove old socket
    rm -f /tmp/muxgeist.sock
    
    # Start daemon in background
    ./muxgeist-daemon &
    DAEMON_PID=$!
    
    # Wait for daemon to start
    sleep 2
    
    # Test daemon
    if ./muxgeist-client status >/dev/null 2>&1; then
        log_success "Daemon started successfully (PID: $DAEMON_PID)"
    else
        log_info "Daemon starting... (may take a moment)"
    fi
}

create_demo_project() {
    log_step "Creating demo project..."
    
    # Create demo directory
    rm -rf "$DEMO_PROJECT_DIR"
    mkdir -p "$DEMO_PROJECT_DIR"
    cd "$DEMO_PROJECT_DIR"
    
    # Create a simple C program with intentional errors
    cat > hello.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>

int main() {
    printf("Hello, Muxgeist!\n");
    
    // Intentional error for demo
    undefined_variable = 42;
    
    return 0;
}
EOF
    
    # Create Makefile
    cat > Makefile << 'EOF'
CC = gcc
CFLAGS = -Wall -Wextra -g

hello: hello.c
	$(CC) $(CFLAGS) -o hello hello.c

clean:
	rm -f hello

.PHONY: clean
EOF
    
    # Create README
    cat > README.md << 'EOF'
# Muxgeist Demo Project

This is a simple C project created to demonstrate Muxgeist's capabilities.

## Building

```bash
make
```

## Running

```bash
./hello
```
EOF
    
    log_success "Demo project created in $DEMO_PROJECT_DIR"
}

setup_demo_session() {
    log_step "Setting up demo tmux session..."
    
    # Kill existing demo session if it exists
    tmux kill-session -t "$DEMO_SESSION" 2>/dev/null || true
    
    # Create new session
    tmux new-session -d -s "$DEMO_SESSION" -c "$DEMO_PROJECT_DIR"
    
    # Set up some initial commands in the session
    tmux send-keys -t "$DEMO_SESSION" "ls -la" Enter
    tmux send-keys -t "$DEMO_SESSION" "cat hello.c" Enter
    tmux send-keys -t "$DEMO_SESSION" "make" Enter
    
    log_success "Demo session '$DEMO_SESSION' created"
}

demonstrate_basic_usage() {
    log_demo "DEMO 1: Basic Muxgeist Usage"
    echo ""
    echo "Let's see how Muxgeist analyzes your terminal context..."
    wait_for_enter
    
    # Test AI service with the demo session
    log_step "Analyzing demo session with AI..."
    
    if python3 muxgeist_ai.py --list; then
        echo ""
        log_step "Getting detailed analysis..."
        python3 muxgeist_ai.py "$DEMO_SESSION" || echo "Analysis completed with mock data"
    else
        log_info "Using mock analysis for demo"
        echo ""
        echo "🌟 Muxgeist Analysis for '$DEMO_SESSION'"
        echo "=" * 50
        echo "I see you're working on C development in $DEMO_PROJECT_DIR."
        echo ""
        echo "Assessment: You're encountering compilation errors that need attention."
        echo ""
        echo "Suggestions:"
        echo "1. Fix the undeclared variable 'undefined_variable' in hello.c"
        echo "2. Consider using debugging tools like gdb for complex issues"
        echo "3. Your Makefile looks good - clean build setup"
        echo ""
        echo "Confidence: 85%"
        echo "⚠️  Requires attention"
    fi
    
    wait_for_enter
}

demonstrate_tmux_integration() {
    log_demo "DEMO 2: Tmux Integration"
    echo ""
    echo "Now let's see the real magic - Muxgeist integrated into tmux!"
    echo ""
    echo "We'll attach to the demo session and show you how to summon Muxgeist."
    echo ""
    echo "Key points:"
    echo "• Press Ctrl+G to summon/dismiss Muxgeist"
    echo "• Muxgeist appears as a side pane"
    echo "• Interactive commands: analyze, refresh, help, quit"
    echo "• Context-aware suggestions based on your current work"
    echo ""
    wait_for_enter
    
    log_step "Attaching to demo session..."
    echo ""
    echo "Once attached:"
    echo "1. Press Ctrl+G to summon Muxgeist"
    echo "2. Try commands: 'analyze', 'help', 'status'"
    echo "3. Press Ctrl+G again to dismiss"
    echo "4. Type 'exit' to return to this demo"
    echo ""
    wait_for_enter
    
    # Attach to the session
    tmux attach-session -t "$DEMO_SESSION"
}

demonstrate_error_detection() {
    log_demo "DEMO 3: Error Detection and Suggestions"
    echo ""
    echo "Let's create some more complex scenarios to show Muxgeist's intelligence..."
    wait_for_enter
    
    # Switch to demo session for commands
    tmux send-keys -t "$DEMO_SESSION" "# Let's try some debugging scenarios" Enter
    tmux send-keys -t "$DEMO_SESSION" "gcc hello.c -o hello" Enter
    tmux send-keys -t "$DEMO_SESSION" "# That should show an error about undefined_variable" Enter
    tmux send-keys -t "$DEMO_SESSION" "gdb hello" Enter
    tmux send-keys -t "$DEMO_SESSION" "quit" Enter
    tmux send-keys -t "$DEMO_SESSION" "valgrind --version" Enter
    
    log_step "Analyzing the debugging session..."
    
    # Analyze the updated context
    sleep 2
    python3 muxgeist_ai.py "$DEMO_SESSION" || echo "Analysis completed"
    
    wait_for_enter
}

show_configuration_options() {
    log_demo "DEMO 4: Configuration and Customization"
    echo ""
    echo "Muxgeist is highly configurable:"
    echo ""
    
    echo "🔧 Configuration Files:"
    echo "• ~/.muxgeist.env - API keys and preferences"
    echo "• ~/.tmux.conf - Keybindings and appearance"
    echo "• Systemd service for auto-start"
    echo ""
    
    echo "🎨 Customization Options:"
    echo "• Keybinding changes (default: Ctrl+G)"
    echo "• Pane size and position"
    echo "• AI provider selection (Anthropic/OpenAI/OpenRouter)"
    echo "• Status bar integration"
    echo ""
    
    echo "🔌 AI Provider Support:"
    python3 muxgeist_ai.py --providers 2>/dev/null || echo "• Multiple AI providers supported"
    echo ""
    
    wait_for_enter
}

cleanup_demo() {
    log_step "Cleaning up demo..."
    
    # Kill demo session
    tmux kill-session -t "$DEMO_SESSION" 2>/dev/null || true
    
    # Stop daemon
    if [ -n "${DAEMON_PID:-}" ]; then
        kill "$DAEMON_PID" 2>/dev/null || true
    fi
    pkill -f muxgeist-daemon 2>/dev/null || true
    
    # Remove demo project
    rm -rf "$DEMO_PROJECT_DIR"
    
    # Clean socket
    rm -f /tmp/muxgeist.sock
    
    log_success "Demo cleanup complete"
}

show_installation_info() {
    echo ""
    echo -e "${BOLD}🚀 Ready to Install Muxgeist?${NC}"
    echo ""
    echo "Run the installer:"
    echo -e "${GREEN}  ./install-muxgeist.sh${NC}"
    echo ""
    echo "Or install manually:"
    echo "1. Build: make clean && make"
    echo "2. Install: cp muxgeist-* ~/.local/bin/"
    echo "3. Configure: source muxgeist.tmux.conf"
    echo "4. Set API keys in ~/.muxgeist.env"
    echo ""
    echo "Documentation and source:"
    echo "• GitHub: (your repository URL)"
    echo "• Issues: (your issues URL)"
    echo ""
}

main() {
    print_banner
    wait_for_enter
    
    # Trap to ensure cleanup
    trap cleanup_demo EXIT
    
    check_prerequisites
    start_daemon
    create_demo_project
    setup_demo_session
    
    demonstrate_basic_usage
    demonstrate_tmux_integration
    demonstrate_error_detection
    show_configuration_options
    
    log_success "Demo complete!"
    show_installation_info
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Muxgeist Complete Demo"
        echo ""
        echo "This script demonstrates the full Muxgeist experience including:"
        echo "• AI-powered context analysis"
        echo "• Tmux integration with summoning"
        echo "• Error detection and suggestions"
        echo "• Configuration options"
        echo ""
        echo "Usage: $0"
        echo ""
        echo "Prerequisites:"
        echo "• tmux installed"
        echo "• Python 3 with pip"
        echo "• gcc/make for building"
        echo "• Muxgeist source code"
        ;;
    *)
        main "$@"
        ;;
esac
