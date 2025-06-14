#!/bin/bash

# Simplified Muxgeist Installation Script
# Now just a wrapper around the Makefile

set -e

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

show_help() {
    echo "Muxgeist Installation Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --user         Use --user pip install (simpler, no venv)"
    echo "  --help         Show this help"
    echo ""
    echo "The installer creates a dedicated Python virtual environment"
    echo "for Muxgeist to avoid conflicts with your development setup."
    echo ""
    echo "Examples:"
    echo "  $0             # Full install with venv (recommended)"
    echo "  $0 --user      # Simple install with --user packages"
}

main() {
    print_header

    # Check if we're in the right directory
    if [ ! -f "Makefile" ] || [ ! -f "muxgeist-daemon.c" ]; then
        echo -e "${RED}❌ Please run from the Muxgeist source directory${NC}"
        exit 1
    fi

    # Parse arguments
    case "${1:-}" in
    --user)
        echo -e "${YELLOW}Installing with --user packages...${NC}"
        make install-user
        ;;
    --help | -h)
        show_help
        exit 0
        ;;
    "")
        echo -e "${YELLOW}Installing with dedicated virtual environment...${NC}"
        make install
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        show_help
        exit 1
        ;;
    esac
}

main "$@"
