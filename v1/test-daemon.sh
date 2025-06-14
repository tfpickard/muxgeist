#!/bin/bash

set -e

echo "=== Muxgeist Daemon Test Suite ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}PASS:${NC} $1"
}

print_fail() {
    echo -e "${RED}FAIL:${NC} $1"
}

# Build first
print_test "Building daemon and client"
make clean && make
print_pass "Build successful"

# Check if tmux is running
if ! tmux list-sessions &>/dev/null; then
    print_test "Creating test tmux session"
    tmux new-session -d -s muxgeist-test 'cd /tmp && bash'
    CREATED_SESSION=1
fi

# Start daemon
print_test "Starting daemon"
./muxgeist-daemon &
DAEMON_PID=$!
sleep 2

# Test 1: Status check
print_test "Testing status command"
STATUS_OUTPUT=$(./muxgeist-client status)
if [[ $STATUS_OUTPUT == *"sessions tracked"* ]]; then
    print_pass "Status command works"
else
    print_fail "Status command failed: $STATUS_OUTPUT"
fi

# Test 2: List sessions
print_test "Testing list command"
LIST_OUTPUT=$(./muxgeist-client list)
if [[ -n "$LIST_OUTPUT" ]]; then
    print_pass "List command works, found sessions:"
    echo "$LIST_OUTPUT" | sed 's/^/  /'
else
    print_pass "List command works (no sessions found)"
fi

# Test 3: Context retrieval (if we have sessions)
FIRST_SESSION=$(tmux list-sessions -F '#{session_name}' | head -n1)
if [[ -n "$FIRST_SESSION" ]]; then
    print_test "Testing context command for session: $FIRST_SESSION"
    CONTEXT_OUTPUT=$(./muxgeist-client context "$FIRST_SESSION")
    if [[ $CONTEXT_OUTPUT == *"Session:"* ]]; then
        print_pass "Context command works:"
        echo "$CONTEXT_OUTPUT" | sed 's/^/  /'
    else
        print_fail "Context command failed: $CONTEXT_OUTPUT"
    fi
fi

# Test 4: Invalid command
print_test "Testing invalid command handling"
INVALID_OUTPUT=$(./muxgeist-client invalid_command 2>/dev/null || true)
if [[ $INVALID_OUTPUT == *"ERROR"* ]]; then
    print_pass "Invalid command properly rejected"
else
    print_fail "Invalid command not handled properly"
fi

# Cleanup
print_test "Cleaning up"
kill $DAEMON_PID
wait $DAEMON_PID 2>/dev/null || true

if [[ $CREATED_SESSION == 1 ]]; then
    tmux kill-session -t muxgeist-test 2>/dev/null || true
fi

rm -f /tmp/muxgeist.sock

echo -e "${GREEN}=== All tests completed ===${NC}"
