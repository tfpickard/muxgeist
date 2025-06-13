# 🌟 Muxgeist

**AI-Powered Terminal Assistant for Tmux**

Muxgeist is an intelligent terminal companion that lives in a hidden tmux pane, analyzes your workflow context, and provides AI-powered insights and suggestions. It understands what you're working on, detects issues, and offers contextual help when you need it.

## ✨ Features

- **🧠 Context-Aware AI**: Analyzes your scrollback, current directory, and workflow patterns
- **⚡ Instant Summoning**: Press `Ctrl+G` to summon/dismiss from any tmux session
- **🔍 Smart Detection**: Recognizes compilation errors, debugging sessions, project types
- **🎯 Targeted Suggestions**: Provides specific, actionable recommendations
- **🔌 Multi-Provider AI**: Supports Anthropic Claude, OpenAI GPT, and OpenRouter
- **🏗️ Project Intelligence**: Understands C/Python/Git workflows and build systems
- **🎨 Seamless Integration**: Minimal setup, maximum productivity

## 🚀 Quick Start

### 1. Install Dependencies

**macOS:**

```bash
brew install tmux python3 gcc make
```

**Linux (Debian/Ubuntu):**

```bash
sudo apt install tmux python3 python3-pip build-essential
```

**Linux (Arch):**

```bash
sudo paru -S tmux python gcc make
```

### 2. Install Muxgeist

```bash
# Clone and build
git clone <repository-url> muxgeist
cd muxgeist

# Run the installer
./install-muxgeist.sh
```

### 3. Configure API Keys

```bash
# Edit the environment file
nvim ~/.muxgeist.env

# Set your API key (choose one):
export ANTHROPIC_API_KEY="your-key-here"
export OPENAI_API_KEY="your-key-here"
export OPENROUTER_API_KEY="your-key-here"

# Load the configuration
source ~/.muxgeist.env
```

### 4. Start Using

```bash
# Start the daemon
muxgeist-daemon &

# Launch tmux
tmux

# Summon Muxgeist
# Press Ctrl+G
```

## 🎮 Usage

### Summoning Muxgeist

- **`Ctrl+G`** - Summon/dismiss Muxgeist pane
- **`Prefix + g`** - Alternative keybinding

### Interactive Commands

Once summoned, Muxgeist provides an interactive interface:

- **`analyze`** or **`a`** - Analyze current session
- **`refresh`** or **`r`** - Force refresh analysis
- **`status`** or **`s`** - Show system status
- **`list`** or **`l`** - List all tracked sessions
- **`help`** or **`h`** - Show help
- **`quit`** or **`q`** - Dismiss Muxgeist
- **`<Enter>`** - Re-analyze session

### Command Line Tools

```bash
# Check daemon status
muxgeist-client status

# Analyze specific session
python3 muxgeist_ai.py session-name

# List all sessions
python3 muxgeist_ai.py --list

# Check available AI providers
python3 muxgeist_ai.py --providers

# Manual pane management
muxgeist-summon --help
muxgeist-dismiss --help
```

## 🔧 Configuration

### Tmux Configuration

Muxgeist automatically adds configuration to `~/.tmux.conf`:

```bash
# Muxgeist keybinding - Ctrl+G to summon/dismiss
bind-key C-g run-shell 'muxgeist-summon'

# Alternative keybinding - Prefix + g
bind-key g run-shell 'muxgeist-summon'

# Status line integration (optional)
set-option -g status-right "#{?#{==:#{pane_title},muxgeist},🌟 ,}..."
```

### Environment Variables

```bash
# AI Provider Configuration
export ANTHROPIC_API_KEY="your-key"           # Anthropic Claude
export OPENAI_API_KEY="your-key"              # OpenAI GPT
export OPENROUTER_API_KEY="your-key"          # OpenRouter (multi-model)

# Provider Selection (auto-detected if not set)
export MUXGEIST_AI_PROVIDER="anthropic"       # anthropic, openai, openrouter

# OpenRouter Model Override
export OPENROUTER_MODEL="anthropic/claude-3.5-sonnet"

# Installation Directory
export MUXGEIST_INSTALL_DIR="$HOME/.local/bin"
```

### Systemd Service (Linux)

```bash
# Enable auto-start
systemctl --user enable muxgeist
systemctl --user start muxgeist

# Check status
systemctl --user status muxgeist
```

## 🧪 Examples

### C Development Workflow

```bash
$ cd my-project
$ make
gcc: error: undefined reference to `missing_function`
# Press Ctrl+G to summon Muxgeist
```

**Muxgeist Analysis:**

```
🌟 I see you're working on C development in /home/user/my-project.

Assessment: You're encountering linker errors that need attention.

Suggestions:
1. Check if you're missing a library link (-lmylib)
2. Verify function declarations in header files
3. Consider using 'nm' to inspect object files

Confidence: 90%
⚠️  Requires attention
```

### Python Development

```bash
$ python3 data_analysis.py
ModuleNotFoundError: No module named 'pandas'
# Press Ctrl+G
```

**Muxgeist Analysis:**

```
🌟 You're working on Python development in /home/user/analytics.

Assessment: Missing Python dependencies detected.

Suggestions:
1. Install missing module: pip install pandas
2. Consider using a virtual environment
3. Add dependencies to requirements.txt

Confidence: 95%
```

## 🏗️ Architecture

### Components

1. **`muxgeist-daemon`** (C) - Monitors tmux sessions and captures context
2. **`muxgeist_ai.py`** (Python) - AI analysis and context processing
3. **`muxgeist-interactive.py`** (Python) - Interactive tmux pane interface
4. **`muxgeist-summon`** (Bash) - Tmux pane management
5. **`muxgeist-dismiss`** (Bash) - Pane cleanup

### Data Flow

```
tmux session → daemon (context capture) → AI service (analysis) → interactive UI → user
```

### Context Analysis

Muxgeist analyzes:

- **Scrollback content** - Commands, outputs, error messages
- **Working directory** - Project structure, file types
- **Process activity** - Running tools, build systems
- **Error patterns** - Compilation failures, runtime errors
- **Tool usage** - Git, debuggers, editors, build systems

## 🛠️ Development

### Building from Source

```bash
# Build daemon
make clean && make

# Install Python dependencies
pip3 install -r requirements.txt

# Run tests
./test-daemon.sh
python3 test-ai-service.py

# Run diagnostic
python3 diagnose.py
```

### Project Structure

```
muxgeist/
├── muxgeist-daemon.c          # Core daemon (C)
├── muxgeist-client.c          # Test client (C)
├── muxgeist_ai.py            # AI service (Python)
├── muxgeist-interactive.py   # Interactive UI (Python)
├── muxgeist-summon           # Tmux integration (Bash)
├── muxgeist-dismiss          # Pane management (Bash)
├── muxgeist.tmux.conf        # Tmux configuration
├── install-muxgeist.sh       # Installer script
├── demo-complete.sh          # Full demo
├── test-*.{sh,py}           # Test suites
└── diagnose.py              # Diagnostic tool
```

### Running the Demo

```bash
# See the complete Muxgeist experience
./demo-complete.sh
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## 📝 License

[Your chosen license]

## 🆘 Troubleshooting

### Common Issues

**Daemon won't start:**

```bash
# Check if socket exists
ls -la /tmp/muxgeist.sock

# Check for running processes
ps aux | grep muxgeist

# Run diagnostic
python3 diagnose.py
```

**AI analysis fails:**

```bash
# Check API keys
python3 muxgeist_ai.py --providers

# Test with mock data
python3 demo-ai.py
```

**Tmux integration not working:**

```bash
# Verify tmux config
tmux show-options -g | grep muxgeist

# Check script permissions
ls -la muxgeist-summon muxgeist-dismiss

# Manual summon
./muxgeist-summon --help
```

### Getting Help

- **Diagnostic tool**: `python3 diagnose.py`
- **Test suites**: `./test-daemon.sh` and `python3 test-ai-service.py`
- **Demo mode**: `./demo-complete.sh`
- **Verbose logging**: Set `MUXGEIST_LOG_LEVEL=DEBUG`

## 🌟 Acknowledgments

Built for terminal enthusiasts who live in tmux and appreciate AI-powered productivity tools.

---

**Happy terminal AI assistance!** 🌟
