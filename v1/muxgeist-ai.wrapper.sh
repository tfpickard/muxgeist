#!/bin/bash
# Muxgeist AI wrapper script

# Get script directory (macOS compatible)
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
else
    # Fallback for macOS without realpath
    SOURCE="$0"
    while [ -h "$SOURCE" ]; do
        DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
fi

VENV_DIR="$(dirname "$SCRIPT_DIR")/share/muxgeist/venv"

if [ -f "$VENV_DIR/bin/python" ]; then
    exec "$VENV_DIR/bin/python" "$SCRIPT_DIR/muxgeist_ai.py" "$@"
else
    # Fallback to system python with --user packages
    exec python3 "$SCRIPT_DIR/muxgeist_ai.py" "$@"
fi
