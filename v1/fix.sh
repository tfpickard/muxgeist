#!/bin/bash

# Simplified Muxgeist Setup - Direct Python calls, no wrappers

echo "🚀 Simplifying Muxgeist setup..."

# 1. Make Python files directly executable
echo "🔧 Making Python files executable..."

# Add proper shebang to muxgeist_ai.py if not present
if ! head -n1 muxgeist_ai.py | grep -q "#!/usr/bin/env python3"; then
    echo "#!/usr/bin/env python3" > /tmp/temp_ai.py
    tail -n +2 muxgeist_ai.py >> /tmp/temp_ai.py
    mv /tmp/temp_ai.py muxgeist_ai.py
fi

# Add proper shebang to muxgeist-interactive.py if not present  
if ! head -n1 muxgeist-interactive.py | grep -q "#!/usr/bin/env python3"; then
    echo "#!/usr/bin/env python3" > /tmp/temp_interactive.py
    tail -n +2 muxgeist-interactive.py >> /tmp/temp_interactive.py
    mv /tmp/temp_interactive.py muxgeist-interactive.py
fi

# Make them executable
chmod +x muxgeist_ai.py muxgeist-interactive.py

# 2. Create a simple, direct tmux summon script
echo "🔧 Creating simplified summon script..."
cat > muxgeist-summon << 'EOF'
#!/bin/bash

# Simple Muxgeist summon - calls Python directly
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MUXGEIST_PANE_TITLE="muxgeist"
MUXGEIST_SIZE="40"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if we're in tmux
if [ -z "$TMUX" ]; then
    echo -e "${RED}❌ Must be run from within tmux${NC}"
    exit 1
fi

# Get current session and window
CURRENT_SESSION=$(tmux display-message -p '#{session_name}')
CURRENT_WINDOW=$(tmux display-message -p '#{window_index}')

# Find existing Muxgeist pane
find_muxgeist_pane() {
    tmux list-panes -t "$CURRENT_SESSION:$CURRENT_WINDOW" -F '#{pane_index} #{pane_title}' |
        grep "$MUXGEIST_PANE_TITLE" |
        cut -d' ' -f1
}

# Check if Muxgeist pane exists and is visible
muxgeist_exists() {
    [ -n "$(find_muxgeist_pane)" ]
}

muxgeist_visible() {
    local pane_id=$(find_muxgeist_pane)
    if [ -n "$pane_id" ]; then
        local width=$(tmux display-message -t "$pane_id" -p '#{pane_width}')
        [ "$width" -gt 5 ]
    else
        return 1
    fi
}

# Create Muxgeist pane
create_muxgeist_pane() {
    echo -e "${YELLOW}🌟 Summoning Muxgeist...${NC}"
    
    # Create wrapper script that sets pane title and runs Python directly
    WRAPPER=$(mktemp)
    cat > "$WRAPPER" << WRAPPER_EOF
#!/bin/bash
printf '\033]2;$MUXGEIST_PANE_TITLE\033\\'
cd "$SCRIPT_DIR"
exec python3 "./muxgeist-interactive.py"
WRAPPER_EOF
    chmod +x "$WRAPPER"
    
    # Create the pane
    if tmux split-window -h -p "$MUXGEIST_SIZE" "$WRAPPER"; then
        sleep 0.5
        tmux last-pane
        echo -e "${GREEN}✅ Muxgeist summoned${NC}"
        
        # Clean up wrapper after delay
        (sleep 10; rm -f "$WRAPPER") &
    else
        echo -e "${RED}❌ Failed to create tmux pane${NC}"
        rm -f "$WRAPPER"
        exit 1
    fi
}

# Show hidden pane
show_muxgeist_pane() {
    local pane_id=$(find_muxgeist_pane)
    tmux resize-pane -t "$pane_id" -x "${MUXGEIST_SIZE}%"
    tmux refresh-client
    echo -e "${GREEN}✅ Muxgeist shown${NC}"
}

# Hide pane
hide_muxgeist_pane() {
    local pane_id=$(find_muxgeist_pane)
    tmux resize-pane -t "$pane_id" -x 1
    tmux select-pane -t 0
    echo -e "${YELLOW}👋 Muxgeist hidden${NC}"
}

# Main logic
if muxgeist_exists; then
    if muxgeist_visible; then
        hide_muxgeist_pane
    else
        show_muxgeist_pane
    fi
else
    create_muxgeist_pane
fi
EOF

chmod +x muxgeist-summon

# 3. Create simple dismiss script
echo "🔧 Creating simplified dismiss script..."
cat > muxgeist-dismiss << 'EOF'
#!/bin/bash

MUXGEIST_PANE_TITLE="muxgeist"

if [ -z "$TMUX" ]; then
    echo "❌ Must be run from within tmux"
    exit 1
fi

CURRENT_SESSION=$(tmux display-message -p '#{session_name}')
CURRENT_WINDOW=$(tmux display-message -p '#{window_index}')

pane_id=$(tmux list-panes -t "$CURRENT_SESSION:$CURRENT_WINDOW" -F '#{pane_index} #{pane_title}' |
    grep "$MUXGEIST_PANE_TITLE" |
    cut -d' ' -f1)

if [ -n "$pane_id" ]; then
    tmux kill-pane -t "$pane_id"
    tmux select-pane -t 0 2>/dev/null || true
    echo "✅ Muxgeist dismissed"
else
    echo "ℹ No Muxgeist pane found"
fi
EOF

chmod +x muxgeist-dismiss

# 4. Create simple tmux config
echo "🔧 Creating simple tmux config..."
cat > muxgeist.tmux.conf << 'EOF'
# Simple Muxgeist tmux configuration

# Main keybinding - Ctrl+G to summon/dismiss
bind-key C-g run-shell 'muxgeist-summon'

# Alternative - Prefix + g
bind-key g run-shell 'muxgeist-summon'

# Optional status line indicator
set-option -g status-right "#{?#{==:#{pane_title},muxgeist},🌟 ,}#[fg=colour233,bg=colour241,bold] %d/%m #[fg=colour233,bg=colour245,bold] %H:%M:%S "
EOF

# 5. Install dependencies directly (no virtual env)
echo "🔧 Installing Python dependencies..."
if command -v pip3 >/dev/null; then
    pip3 install --user anthropic openai PyYAML
    echo "✅ Dependencies installed with --user"
else
    echo "⚠️ pip3 not found - install manually: pip3 install anthropic openai PyYAML"
fi

# 6. Build daemon
echo "🔧 Building daemon..."
make clean && make

# 7. Setup tmux config if desired
echo ""
echo "✅ Simplified setup complete!"
echo ""
echo "📁 What's created:"
echo "  • muxgeist-daemon (C binary)"  
echo "  • muxgeist_ai.py (executable Python script)"
echo "  • muxgeist-interactive.py (executable Python script)"
echo "  • muxgeist-summon (simple bash script)"
echo "  • muxgeist-dismiss (simple bash script)"
echo "  • muxgeist.tmux.conf (tmux config)"
echo ""
echo "🚀 To use:"
echo "  1. Set API key: export ANTHROPIC_API_KEY='your-key'"
echo "  2. Start daemon: ./muxgeist-daemon &"
echo "  3. Add to ~/.tmux.conf: source-file $(pwd)/muxgeist.tmux.conf"
echo "  4. Reload tmux: tmux source ~/.tmux.conf"
echo "  5. Press Ctrl+G in any tmux session"
echo ""
echo "🧪 Test manually:"
echo "  • ./muxgeist_ai.py --list"
echo "  • ./muxgeist-interactive.py (from tmux session)"
echo ""
echo "No wrappers, no virtual envs, no complex installation - just direct Python calls!"
