#!/bin/bash

set -e

echo "=== Muxgeist AI Service Setup ==="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}STEP:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check Python version
print_step "Checking Python version"
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    print_success "Python $PYTHON_VERSION found"
else
    print_error "Python 3 not found. Please install Python 3.8+"
    exit 1
fi

# Check if we're in a virtual environment
if [[ "$VIRTUAL_ENV" != "" ]]; then
    print_success "Virtual environment active: $VIRTUAL_ENV"
else
    print_warning "No virtual environment detected. Recommended to create one:"
    echo "  python3 -m venv venv"
    echo "  source venv/bin/activate"
    echo ""
    read -p "Continue with system Python? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Install Python dependencies
print_step "Installing Python dependencies"
if pip3 install -r requirements.txt; then
    print_success "Dependencies installed successfully"
else
    print_error "Failed to install dependencies"
    exit 1
fi

# Check for API keys
print_step "Checking API key configuration"
API_KEY_FOUND=false

if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    print_success "ANTHROPIC_API_KEY found in environment"
    API_KEY_FOUND=true
fi

if [[ -n "$OPENAI_API_KEY" ]]; then
    print_success "OPENAI_API_KEY found in environment"
    API_KEY_FOUND=true
fi

if [[ "$API_KEY_FOUND" == "false" ]]; then
    print_warning "No AI API keys found in environment"
    echo "To use AI features, set one of:"
    echo "  export ANTHROPIC_API_KEY='your-key-here'"
    echo "  export OPENAI_API_KEY='your-key-here'"
    echo ""
    echo "For testing without API keys, the service includes mock responses."
fi

# Check if daemon is running
print_step "Checking if muxgeist daemon is running"
if [[ -S "/tmp/muxgeist.sock" ]]; then
    print_success "Daemon socket found"
else
    print_warning "Daemon not running. Start it with:"
    echo "  ./muxgeist-daemon &"
fi

# Create .env template if it doesn't exist
if [[ ! -f ".env" ]]; then
    print_step "Creating .env template"
    cat >.env <<'EOF'
# Muxgeist AI Configuration
# Uncomment and set your preferred AI provider

# For Anthropic Claude
# ANTHROPIC_API_KEY=your-anthropic-key-here

# For OpenAI GPT
# OPENAI_API_KEY=your-openai-key-here

# Default AI provider (anthropic or openai)
# MUXGEIST_AI_PROVIDER=anthropic

# Log level (DEBUG, INFO, WARNING, ERROR)
# MUXGEIST_LOG_LEVEL=INFO
EOF
    print_success "Created .env template file"
    echo "  Edit .env to configure your API keys"
fi

# Run tests
print_step "Running test suite"
if python3 test-ai-service.py; then
    print_success "Test suite completed"
else
    print_warning "Some tests failed - check output above"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Quick start:"
echo "  1. Start the daemon: ./muxgeist-daemon &"
echo "  2. List sessions: python3 muxgeist_ai.py --list"
echo "  3. Analyze session: python3 muxgeist_ai.py <session-name>"
echo ""
echo "For AI features, configure API keys in .env file"
