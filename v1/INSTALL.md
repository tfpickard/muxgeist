# Muxgeist Installation Guide

## TL;DR - Quick Install

```bash
# Clone and install
git clone <repository> muxgeist
cd muxgeist

# Option 1: Full install with dedicated venv (recommended)
make install

# Option 2: Simple install with --user packages
make install-user

# Configure your API key
nvim ~/.config/muxgeist/config.yaml

# Start daemon and use
muxgeist-daemon &
# In tmux, press Ctrl+G
```

## Installation Methods

### Method 1: Dedicated Virtual Environment (Recommended)

This creates a dedicated Python venv for Muxgeist, completely separate from your development environment:

```bash
make install
```

**Pros:**

- Completely isolated from your dev environment
- No conflicts with your virtualenvwrapper/poetry/etc setup
- System-wide availability
- Clean uninstall

**Cons:**

- Uses more disk space
- More complex setup

### Method 2: User Packages (Simpler)

This uses `pip install --user` to install dependencies:

```bash
make install-user
```

**Pros:**

- Simpler setup
- Faster installation
- Uses system Python

**Cons:**

- May conflict with other Python projects
- Harder to uninstall cleanly

## What Gets Installed

```
~/.local/bin/              # Executables
├── muxgeist-daemon        # C daemon
├── muxgeist-client        # C client
├── muxgeist-ai            # Python wrapper (method 1)
├── muxgeist-interactive   # Python wrapper (method 1)
├── muxgeist_ai.py         # Direct Python (method 2)
├── muxgeist-interactive.py # Direct Python (method 2)
├── muxgeist-summon        # Shell script
└── muxgeist-dismiss       # Shell script

~/.local/share/muxgeist/   # Shared files (method 1 only)
└── venv/                  # Dedicated Python environment

~/.config/muxgeist/        # Configuration
├── config.yaml            # Main config file
├── interactive.log        # Runtime logs
└── summon.log             # Debug logs

~/.tmux.conf               # Updated with keybindings
```

## Configuration

Edit `~/.config/muxgeist/config.yaml`:

```yaml
ai:
  provider: null # Auto-detected
  anthropic:
    api_key: "sk-ant-api03-your-key-here"
    model: "claude-3-5-sonnet-20241022"
  # ... other providers
```

## Troubleshooting

### Check Installation

```bash
make debug-install          # Show installation paths
make test-installed         # Test installed version
muxgeist-ai --config        # Check configuration
```

### Fix PATH Issues

```bash
# Add to your shell rc file (~/.zshrc, ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"
```

### Virtual Environment Issues

```bash
# Check if venv exists and works
ls -la ~/.local/share/muxgeist/venv/bin/python

# Recreate venv if needed
rm -rf ~/.local/share/muxgeist/venv
make venv
```

### Tmux Integration Issues

```bash
# Test the summon script
./muxgeist-summon --test
./muxgeist-summon --debug

# Check logs
tail -f ~/.config/muxgeist/summon.log
tail -f ~/.config/muxgeist/interactive.log
```

## Uninstalling

```bash
make uninstall              # Remove binaries and venv
rm -rf ~/.config/muxgeist   # Remove config (optional)
```

## Development Setup

If you want to develop on Muxgeist itself:

```bash
# Create development environment
make dev-setup

# Activate venv
source ~/.local/share/muxgeist/venv/bin/activate

# Now you can edit and test
make test
```

This keeps the development venv separate from your workon/mkvenv setup.
