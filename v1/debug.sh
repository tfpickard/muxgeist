# Create debug script
cat >debug_panes.sh <<'EOF'
#!/bin/bash

echo "🔍 Debugging multi-pane capture..."

SESSION_NAME=$(tmux display-message -p '#{session_name}')
echo "Current session: $SESSION_NAME"

echo ""
echo "1. Testing tmux pane listing directly:"
tmux list-panes -t "$SESSION_NAME" -F '#{window_index}.#{pane_index}:#{pane_title}:#{pane_current_command}'

echo ""
echo "2. Testing daemon context retrieval:"
echo "Daemon response:"
./muxgeist-client context "$SESSION_NAME"

echo ""
echo "3. Testing if daemon is using new capture_all_panes function:"
if grep -q "capture_all_panes" muxgeist-daemon.c; then
    echo "✅ capture_all_panes function found in daemon"
else
    echo "❌ capture_all_panes function missing from daemon"
fi

echo ""
echo "4. Testing AI service scrollback parsing:"
python3 << 'PYTHON_EOF'
import sys
sys.path.insert(0, '.')
from muxgeist_ai import ContextAnalyzer

# Test multi-pane parsing
test_scrollback = """
=== PANE 0.0 (shell) ===
$ ls -la
total 64
drwxr-xr-x  15 tom  staff   480 Jun 13 22:41 .
drwxr-xr-x   8 tom  staff   256 Jun 13 19:21 ..

=== PANE 0.1 (muxgeist) ===
🌟 MUXGEIST │ Session: test │ 22:41:32
Welcome! I'm analyzing your session...
"""

analyzer = ContextAnalyzer()

if hasattr(analyzer, 'parse_multi_pane_scrollback'):
    panes = analyzer.parse_multi_pane_scrollback(test_scrollback)
    print(f"✅ Multi-pane parsing works: {len(panes)} panes found")
    print(f"   Panes: {list(panes.keys())}")
else:
    print("❌ parse_multi_pane_scrollback method missing")

# Test full analysis
try:
    analysis = analyzer.analyze_scrollback(test_scrollback)
    print(f"✅ Analysis works: {analysis.get('panes_analyzed', 'No panes key')}")
except Exception as e:
    print(f"❌ Analysis failed: {e}")
PYTHON_EOF

echo ""
echo "5. Current daemon scrollback capture (first 500 chars):"
./muxgeist-client context "$SESSION_NAME" | grep -A 20 "Scrollback:" | head -30
EOF

chmod +x debug_panes.sh
./debug_panes.sh
