# Installation directories
PREFIX ?= /usr/local
INSTALL_DIR ?= $(HOME)/.local
BIN_DIR = $(INSTALL_DIR)/bin
SHARE_DIR = $(INSTALL_DIR)/share/muxgeist
VENV_DIR = $(SHARE_DIR)/venv
CONFIG_DIR = $(HOME)/.config/muxgeist

# Detect Python (prefer brew python on macOS, then python3)
PYTHON := $(shell which python3.11 2>/dev/null || which python3 2>/dev/null || echo python3)

# Source files
DAEMON_SRC = muxgeist-daemon.c
CLIENT_SRC = muxgeist-client.c
DAEMON_BIN = muxgeist-daemon
CLIENT_BIN = muxgeist-client

# Python files
PYTHON_FILES = muxgeist_ai.py muxgeist-interactive.py
SHELL_SCRIPTS = muxgeist-summon muxgeist-dismiss
CONFIG_FILES = config.template.yaml muxgeist.tmux.conf
WRAPPER_TEMPLATES = muxgeist-ai.wrapper.sh muxgeist-interactive.wrapper.sh

.PHONY: all clean test install uninstall venv check-deps install-deps install-config

all: $(DAEMON_BIN) $(CLIENT_BIN)

$(DAEMON_BIN): $(DAEMON_SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(CLIENT_BIN): $(CLIENT_SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Check system dependencies
check-deps:
	@echo "🔍 Checking dependencies..."
	@command -v tmux >/dev/null || (echo "❌ tmux not found. Install with: brew install tmux" && exit 1)
	@command -v $(PYTHON) >/dev/null || (echo "❌ Python not found" && exit 1)
	@echo "✅ System dependencies OK"
	@echo "   Python: $(shell $(PYTHON) --version)"
	@echo "   Tmux: $(shell tmux -V)"
	@PYTHON_VERSION=$($(PYTHON) -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"); \
	if [ "$(echo "$PYTHON_VERSION >= 3.13" | bc -l 2>/dev/null || echo 0)" = "1" ]; then \
		echo "   💡 Python 3.13+ detected - use 'make install' for best compatibility"; \
	fi

# Create virtual environment for muxgeist
venv: check-deps
	@echo "🐍 Setting up Python virtual environment..."
	@mkdir -p $(SHARE_DIR)
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "   Creating venv at $(VENV_DIR)"; \
		$(PYTHON) -m venv $(VENV_DIR); \
	fi
	@echo "   Installing Python dependencies..."
	@$(VENV_DIR)/bin/pip install --upgrade pip
	@$(VENV_DIR)/bin/pip install -r requirements.txt
	@echo "✅ Virtual environment ready"

# Install Python dependencies (alternative to venv, uses --user)
install-deps: check-deps
	@echo "🐍 Installing Python dependencies..."
	@if $(PYTHON) -m pip install --user -r requirements.txt 2>/dev/null; then \
		echo "✅ Dependencies installed to user site-packages"; \
	elif $(PYTHON) -m pip install --user --break-system-packages -r requirements.txt 2>/dev/null; then \
		echo "✅ Dependencies installed with --break-system-packages"; \
		echo "⚠️  Note: Using --break-system-packages due to PEP 668"; \
	else \
		echo "❌ Failed to install dependencies"; \
		echo ""; \
		echo "Python 3.13+ blocks --user installs. Use 'make install' instead."; \
		echo "This creates a dedicated venv for Muxgeist (recommended)."; \
		exit 1; \
	fi

# Install configuration files
install-config:
	@echo "📁 Setting up configuration..."
	@mkdir -p $(CONFIG_DIR)
	@if [ ! -f "$(CONFIG_DIR)/config.yaml" ]; then \
		echo "   Creating default config file..."; \
		if [ -f "config.template.yaml" ]; then \
			cp config.template.yaml "$(CONFIG_DIR)/config.yaml"; \
		elif [ -f "$(SHARE_DIR)/config.template.yaml" ]; then \
			cp "$(SHARE_DIR)/config.template.yaml" "$(CONFIG_DIR)/config.yaml"; \
		else \
			printf "ai:\n" > "$(CONFIG_DIR)/config.yaml"; \
			printf "  provider: null  # Will be auto-detected\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "  anthropic:\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "    api_key: null  # Set your API key here\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "    model: \"claude-3-5-sonnet-20241022\"\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "  openai:\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "    api_key: null\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "    model: \"gpt-4o\"\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "  openrouter:\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "    api_key: null\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "    model: \"anthropic/claude-3.5-sonnet\"\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "\ndaemon:\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "  socket_path: \"/tmp/muxgeist.sock\"\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "\nui:\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "  pane_size: \"40\"\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "  pane_title: \"muxgeist\"\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "\nlogging:\n" >> "$(CONFIG_DIR)/config.yaml"; \
			printf "  level: \"INFO\"\n" >> "$(CONFIG_DIR)/config.yaml"; \
		fi; \
		echo "   📝 Edit $(CONFIG_DIR)/config.yaml to set your API keys"; \
	else \
		echo "   ✅ Config file already exists"; \
	fi

# Create wrapper scripts that use the venv
create-wrappers:
	@echo "📜 Creating wrapper scripts..."
	# @mkdir -p $(BIN_DIR)
	
	# Create muxgeist-ai wrapper
	# @chmod +x $(BIN_DIR)/muxgeist-ai
	
	# Create muxgeist-interactive wrapper  
	# @chmod +x $(BIN_DIR)/muxgeist-interactive

# Update muxgeist-summon to use the wrapper
update-summon:
	@echo "🔧 Updating summon script..."
	@mkdir -p $(BIN_DIR)
	@sed 's|muxgeist-interactive\.py|muxgeist-interactive|g' muxgeist-summon > $(BIN_DIR)/muxgeist-summon
	@chmod +x $(BIN_DIR)/muxgeist-summon

# Full installation with venv (recommended)
install: all venv install-config
	@echo "🚀 Installing Muxgeist..."
	@mkdir -p $(BIN_DIR) $(SHARE_DIR)
	
	# Install binaries
	@install -m 755 $(DAEMON_BIN) $(BIN_DIR)/
	@install -m 755 $(CLIENT_BIN) $(BIN_DIR)/
	
	# Install Python scripts
	@install -m 755 $(PYTHON_FILES) $(BIN_DIR)/
	
	# Install shell scripts
	@install -m 755 $(SHELL_SCRIPTS) $(BIN_DIR)/
	
	# Install config template and wrapper templates for future use
	@install -m 644 config.template.yaml $(SHARE_DIR)/ 2>/dev/null || true
	@install -m 644 $(WRAPPER_TEMPLATES) $(SHARE_DIR)/ 2>/dev/null || true
	
	# Create wrappers for Python scripts
	@$(MAKE) create-wrappers
	@$(MAKE) update-summon
	
	# Setup tmux configuration
	@$(MAKE) install-tmux-config
	
	@echo ""
	@echo "✅ Muxgeist installed successfully!"
	@echo ""
	@echo "📍 Installation directory: $(INSTALL_DIR)"
	@echo "📍 Configuration: $(CONFIG_DIR)/config.yaml"
	@echo "📍 Virtual environment: $(VENV_DIR)"
	@echo ""
	@echo "Next steps:"
	@echo "1. Add $(BIN_DIR) to your PATH if not already there"
	@echo "2. Edit $(CONFIG_DIR)/config.yaml to set your AI API keys"
	@echo "3. Start daemon: muxgeist-daemon &"
	@echo "4. In tmux, press Ctrl+G to summon Muxgeist"

# Alternative installation using --user (no venv)
install-user: all install-deps install-config
	@echo "🚀 Installing Muxgeist (user mode)..."
	@mkdir -p $(BIN_DIR)
	
	# Install binaries
	@install -m 755 $(DAEMON_BIN) $(BIN_DIR)/
	@install -m 755 $(CLIENT_BIN) $(BIN_DIR)/
	
	# Install Python scripts
	@install -m 755 $(PYTHON_FILES) $(BIN_DIR)/
	
	# Install shell scripts with python3 fallback
	@sed 's|python3.*muxgeist-interactive\.py|python3 $(BIN_DIR)/muxgeist-interactive.py|g' muxgeist-summon > $(BIN_DIR)/muxgeist-summon
	@install -m 755 muxgeist-dismiss $(BIN_DIR)/
	@chmod +x $(BIN_DIR)/muxgeist-summon
	
	# Setup tmux configuration
	@$(MAKE) install-tmux-config
	
	@echo ""
	@echo "✅ Muxgeist installed successfully (user mode)!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Edit $(CONFIG_DIR)/config.yaml to set your AI API keys"
	@echo "2. Start daemon: muxgeist-daemon &"
	@echo "3. In tmux, press Ctrl+G to summon Muxgeist"

# Install tmux configuration
install-tmux-config:
	@echo "⚙️  Setting up tmux configuration..."
	@if [ ! -f "$(HOME)/.tmux.conf" ]; then \
		echo "   Creating new .tmux.conf"; \
		cp muxgeist.tmux.conf $(HOME)/.tmux.conf; \
	elif ! grep -q "muxgeist" $(HOME)/.tmux.conf; then \
		echo "   Adding Muxgeist config to existing .tmux.conf"; \
		echo "" >> $(HOME)/.tmux.conf; \
		echo "# Muxgeist Configuration" >> $(HOME)/.tmux.conf; \
		cat muxgeist.tmux.conf >> $(HOME)/.tmux.conf; \
		echo "   📝 Backed up original to .tmux.conf.backup"; \
		cp $(HOME)/.tmux.conf $(HOME)/.tmux.conf.backup; \
	else \
		echo "   ✅ Muxgeist config already present"; \
	fi

# Uninstall everything
uninstall:
	@echo "🗑️  Uninstalling Muxgeist..."
	@rm -f $(BIN_DIR)/muxgeist-*
	@rm -rf $(SHARE_DIR)
	@echo "   Configuration kept at $(CONFIG_DIR)"
	@echo "   Remove manually if desired: rm -rf $(CONFIG_DIR)"

# Test installation
test: $(DAEMON_BIN) $(CLIENT_BIN)
	@echo "🧪 Testing Muxgeist..."
	@echo "1. Starting daemon in background..."
	@./$(DAEMON_BIN) &
	@DAEMON_PID=$$!; \
	sleep 2; \
	echo "2. Testing status command..."; \
	./$(CLIENT_BIN) status; \
	echo "3. Testing list command..."; \
	./$(CLIENT_BIN) list; \
	echo "4. Testing AI service..."; \
	$(PYTHON) -c "import sys; sys.path.insert(0, '.'); from muxgeist_ai import MuxgeistAI; print('✅ AI service imports OK')" || echo "⚠️  AI service needs dependencies"; \
	echo "5. Stopping daemon..."; \
	kill $$DAEMON_PID; \
	wait $$DAEMON_PID 2>/dev/null || true; \
	echo "✅ Test complete"

# Test installed version
test-installed:
	@echo "🧪 Testing installed Muxgeist..."
	@command -v muxgeist-daemon >/dev/null || (echo "❌ muxgeist-daemon not in PATH" && exit 1)
	@muxgeist-ai --providers
	@echo "✅ Installed version OK"

# Development targets
dev-setup: venv
	@echo "👨‍💻 Setting up development environment..."
	@$(VENV_DIR)/bin/pip install -e .
	@echo "✅ Development setup complete"
	@echo "   Activate with: source $(VENV_DIR)/bin/activate"

# Clean up build artifacts
clean:
	rm -f $(DAEMON_BIN) $(CLIENT_BIN)
	rm -f /tmp/muxgeist.sock
	rm -rf *.dSYM/

# Clean everything including venv
distclean: clean
	rm -rf $(SHARE_DIR)

# Debug installation
debug-install:
	@echo "🐛 Installation Debug Info:"
	@echo "   INSTALL_DIR: $(INSTALL_DIR)"
	@echo "   BIN_DIR: $(BIN_DIR)"
	@echo "   VENV_DIR: $(VENV_DIR)"
	@echo "   CONFIG_DIR: $(CONFIG_DIR)"
	@echo "   PYTHON: $(PYTHON) ($(shell $(PYTHON) --version 2>/dev/null || echo 'not found'))"
	@echo "   PATH: $$PATH"
	@echo ""
	@echo "File check:"
	@ls -la $(BIN_DIR)/muxgeist-* 2>/dev/null || echo "   No muxgeist files in $(BIN_DIR)"
	@echo ""
	@echo "Venv check:"
	@ls -la $(VENV_DIR)/bin/python* 2>/dev/null || echo "   No venv at $(VENV_DIR)"

# Help target
help:
	@echo "Muxgeist Build System"
	@echo "===================="
	@echo ""
	@echo "⚠️  For Python 3.13+, use 'make install' (creates dedicated venv)"
	@echo ""
	@echo "Main targets:"
	@echo "  all            - Build daemon and client"
	@echo "  install        - Full install with dedicated venv (recommended)"
	@echo "  install-user   - Install using --user packages (Python <3.13)"
	@echo "  test           - Test build"
	@echo "  test-installed - Test installed version"
	@echo "  uninstall      - Remove installation"
	@echo "  clean          - Remove build artifacts"
	@echo ""
	@echo "Development:"
	@echo "  venv           - Create Python virtual environment"
	@echo "  dev-setup      - Setup development environment"
	@echo "  debug-install  - Show installation debug info"
	@echo ""
	@echo "Configuration:"
	@echo "  PREFIX         - Installation prefix (default: /usr/local)"
	@echo "  INSTALL_DIR    - Install directory (default: ~/.local)"
	@echo ""
	@echo "Examples:"
	@echo "  make install                    # Install with venv (recommended)"
	@echo "  make install-user              # Install with --user (older Python)"
	@echo "  make INSTALL_DIR=/opt/muxgeist install  # Custom location"

.SECONDARY:
