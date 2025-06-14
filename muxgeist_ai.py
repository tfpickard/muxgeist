#!/usr/bin/env python3

import socket
import json
import re
import os
import sys
import time
import logging
import yaml
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path

import openai
import yaml
from anthropic import Anthropic

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@dataclass
class SessionContext:
    session_id: str
    cwd: str
    pane: str
    last_activity: int
    scrollback: str
    scrollback_length: int


@dataclass
class AnalysisResult:
    session_context: SessionContext
    analysis: str
    suggestions: List[str]
    confidence: float
    requires_attention: bool


class ConfigManager:
    """Manages configuration from YAML file and environment variables"""

    def __init__(self):
        self.config_dir = Path.home() / ".config" / "muxgeist"
        self.config_file = self.config_dir / "config.yaml"
        self.config = self._load_config()

    def _load_config(self) -> Dict:
        """Load configuration from YAML file, create if missing"""
        config = {}

        if self.config_file.exists():
            try:
                with open(self.config_file, "r") as f:
                    config = yaml.safe_load(f) or {}
                logger.info(f"Loaded config from {self.config_file}")
            except Exception as e:
                logger.warning(f"Failed to load config file: {e}")

        # If no config file exists, create default one
        if not config:
            config = self._create_default_config()

        return config

    def _create_default_config(self) -> Dict:
        """Create default configuration file"""
        default_config = {
            "ai": {
                "provider": None,  # Will be auto-detected
                "anthropic": {"api_key": None, "model": "claude-3-5-sonnet-20241022"},
                "openai": {"api_key": None, "model": "gpt-4o"},
                "openrouter": {"api_key": None, "model": "anthropic/claude-3.5-sonnet"},
            },
            "daemon": {"socket_path": "/tmp/muxgeist.sock"},
            "ui": {"pane_size": "40", "pane_title": "muxgeist"},
            "logging": {"level": "INFO"},
        }

        # Create config directory if it doesn't exist
        self.config_dir.mkdir(parents=True, exist_ok=True)

        try:
            with open(self.config_file, "w") as f:
                yaml.dump(default_config, f, default_flow_style=False, indent=2)
            logger.info(f"Created default config at {self.config_file}")
        except Exception as e:
            logger.warning(f"Failed to create config file: {e}")

        return default_config

    def get(self, key_path: str, default=None):
        """Get configuration value with dot notation (e.g., 'ai.anthropic.api_key')"""
        # First try environment variable
        env_key = key_path.upper().replace(".", "_")
        env_value = os.getenv(env_key)
        if env_value is not None:
            return env_value

        # Then try config file
        keys = key_path.split(".")
        value = self.config

        for key in keys:
            if isinstance(value, dict) and key in value:
                value = value[key]
            else:
                return default

        return value

    def get_api_key(self, provider: str) -> Optional[str]:
        """Get API key for specific provider with environment fallback"""
        # Check environment variables first (for backward compatibility)
        env_keys = {
            "anthropic": "ANTHROPIC_API_KEY",
            "openai": "OPENAI_API_KEY",
            "openrouter": "OPENROUTER_API_KEY",
        }

        if provider in env_keys:
            env_key = os.getenv(env_keys[provider])
            if env_key:
                return env_key

        # Then check config file
        return self.get(f"ai.{provider}.api_key")

    def get_model(self, provider: str) -> str:
        """Get model for specific provider"""
        # Check for provider-specific environment override
        env_model = os.getenv(f"{provider.upper()}_MODEL")
        if env_model:
            return env_model

        # Get from config with provider-specific default
        defaults = {
            "anthropic": "claude-3-5-sonnet-20241022",
            "openai": "gpt-4o",
            "openrouter": "anthropic/claude-3.5-sonnet",
        }

        return self.get(f"ai.{provider}.model", defaults.get(provider, "unknown"))


class DaemonClient:
    """Client for communicating with muxgeist daemon"""

    def __init__(self, config_manager: ConfigManager = None):
        self.config = config_manager or ConfigManager()
        self.socket_path = self.config.get("daemon.socket_path", "/tmp/muxgeist.sock")

    def _send_command(self, command: str) -> str:
        """Send command to daemon and return response"""
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(self.socket_path)
            sock.send(command.encode())

            response = sock.recv(8192).decode()
            sock.close()
            return response
        except Exception as e:
            logger.error(f"Failed to communicate with daemon: {e}")
            return ""

    def get_status(self) -> str:
        """Get daemon status"""
        return self._send_command("status")

    def list_sessions(self) -> List[str]:
        """Get list of tracked sessions"""
        response = self._send_command("list")
        if not response:
            return []

        sessions = []
        for line in response.strip().split("\n"):
            if line and not line.startswith("ERROR"):
                session_name = line.split(" ")[0]
                sessions.append(session_name)
        return sessions

    def get_context(self, session_id: str) -> Optional[SessionContext]:
        """Get context for specific session"""
        response = self._send_command(f"context:{session_id}")
        if not response or response.startswith("ERROR"):
            return None

        # Parse the response
        lines = response.strip().split("\n")
        context_data = {}
        scrollback_lines = []
        parsing_scrollback = False

        for line in lines:
            if ":" in line and not parsing_scrollback:
                key, value = line.split(":", 1)
                key = key.strip().lower()
                value = value.strip()

                if key == "session":
                    context_data["session_id"] = value
                elif key == "cwd":
                    context_data["cwd"] = value
                elif key == "pane":
                    context_data["pane"] = value
                elif key == "last activity":
                    context_data["last_activity"] = int(value)
                elif key == "scrollback length":
                    context_data["scrollback_length"] = int(value)
                elif key == "scrollback":
                    parsing_scrollback = True
                    if value:  # If there's content on same line
                        scrollback_lines.append(value)
            elif parsing_scrollback:
                scrollback_lines.append(line)

        # Join scrollback content
        context_data["scrollback"] = "\n".join(scrollback_lines)

        # Get actual scrollback from tmux if not in daemon response
        if not context_data.get("scrollback") and context_data.get("session_id"):
            try:
                import subprocess

                result = subprocess.run(
                    ["tmux", "capture-pane", "-t", context_data["session_id"], "-p"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if result.returncode == 0:
                    context_data["scrollback"] = result.stdout
                    context_data["scrollback_length"] = len(result.stdout)
                    logger.info(
                        f"Retrieved scrollback directly from tmux ({len(result.stdout)} chars)"
                    )
            except Exception as e:
                logger.warning(f"Could not get scrollback from tmux: {e}")
                context_data["scrollback"] = ""

        return SessionContext(**context_data)


class ContextAnalyzer:
    """Analyzes terminal context to extract meaningful information"""

    def __init__(self):
        self.error_patterns = [
            (r"error:", "compilation or runtime error"),
            (r"permission denied", "permission issue"),
            (r"no such file", "missing file or path"),
            (r"command not found", "missing command or typo"),
            (r"segmentation fault", "memory access error"),
            (r"killed", "process terminated"),
        ]

        self.tool_patterns = [
            (r"gcc|clang", "c compilation"),
            (r"python|pip", "python development"),
            (r"git", "version control"),
            (r"make|cmake", "build system"),
            (r"gdb|valgrind", "debugging"),
            (r"nvim|vim", "text editing"),
            (r"tmux", "terminal multiplexing"),
        ]

    def parse_multi_pane_scrollback(self, scrollback: str) -> Dict[str, str]:
        """Parse multi-pane scrollback into individual pane contents"""
        panes = {}

        if "=== PANE" not in scrollback:
            # Single pane format
            panes["main"] = scrollback
            return panes

        # Split by pane headers
        sections = scrollback.split("=== PANE ")
        for section in sections[1:]:  # Skip first empty section
            lines = section.split("\n", 1)
            if len(lines) >= 2:
                # Extract pane ID and title from header like "2.1 (belzebu) ==="
                header = lines[0].split(" ===")[0]
                pane_content = lines[1] if len(lines) > 1 else ""

                # Clean up header to get pane info
                pane_info = header.strip("()").replace("(", " - ")
                panes[pane_info] = pane_content

        return panes

    def analyze_scrollback(self, scrollback: str) -> Dict[str, any]:
        """Analyze scrollback content for patterns and context"""

        analysis = {
            "errors_found": [],
            "tools_detected": [],
            "recent_commands": [],
            "working_on": "unknown",
            "sentiment": "neutral",
            "panes_analyzed": [],
            "primary_activity": "unknown",
        }
        if not scrollback:
            return analysis

        # Parse multi-pane content
        panes = self.parse_multi_pane_scrollback(scrollback)
        analysis["panes_analyzed"] = list(panes.keys())

        # Analyze each pane
        all_lines = []
        for pane_id, pane_content in panes.items():
            lines = pane_content.split("\n")
            all_lines.extend(lines)

            # Track which pane has the most activity
            if len(lines) > 10:  # Significant content
                analysis["primary_activity"] = pane_id

        # Use recent lines from all panes for analysis
        lines = all_lines
        # lines = scrollback.split("\n")
        recent_lines = lines[-50:]  # Look at last 50 lines

        # Detect errors
        for line in recent_lines:
            line_lower = line.lower()
            for pattern, description in self.error_patterns:
                if re.search(pattern, line_lower):
                    analysis["errors_found"].append(
                        {"line": line.strip(), "type": description}
                    )

        # Detect tools
        for line in recent_lines:
            line_lower = line.lower()
            for pattern, tool_type in self.tool_patterns:
                if re.search(pattern, line_lower):
                    if tool_type not in analysis["tools_detected"]:
                        analysis["tools_detected"].append(tool_type)

        # Extract recent commands (simple heuristic)
        for line in recent_lines:
            if line.startswith("$ ") or line.startswith("# "):
                cmd = line[2:].strip()
                if cmd and len(cmd) < 100:  # Reasonable command length
                    analysis["recent_commands"].append(cmd)

        # Determine what user is working on
        if "c compilation" in analysis["tools_detected"]:
            analysis["working_on"] = "c/c++ development"
        elif "python development" in analysis["tools_detected"]:
            analysis["working_on"] = "python development"
        elif "debugging" in analysis["tools_detected"]:
            analysis["working_on"] = "debugging session"
        elif "build system" in analysis["tools_detected"]:
            analysis["working_on"] = "building project"

        # Simple sentiment analysis
        if analysis["errors_found"]:
            analysis["sentiment"] = (
                "frustrated" if len(analysis["errors_found"]) > 3 else "debugging"
            )
        elif analysis["recent_commands"]:
            analysis["sentiment"] = "productive"

        return analysis

    def analyze_project_context(self, cwd: str) -> Dict[str, any]:
        """Analyze project context from current working directory"""
        context = {
            "project_type": "unknown",
            "files_of_interest": [],
            "build_system": None,
        }

        try:
            cwd_path = Path(cwd)
            if not cwd_path.exists():
                return context

            files = list(cwd_path.iterdir())
            file_names = [f.name for f in files if f.is_file()]

            # Detect project type
            if "Makefile" in file_names or any(f.endswith(".c") for f in file_names):
                context["project_type"] = "c/c++ project"
                context["build_system"] = "make"
            elif "requirements.txt" in file_names or "setup.py" in file_names:
                context["project_type"] = "python project"
            elif ".git" in [f.name for f in files if f.is_dir()]:
                context["project_type"] += " (git repository)"

            # Find interesting files
            interesting_extensions = [".c", ".h", ".py", ".sh", ".md", ".txt"]
            for filename in file_names[:10]:  # Limit to avoid spam
                if any(filename.endswith(ext) for ext in interesting_extensions):
                    context["files_of_interest"].append(filename)

        except Exception as e:
            logger.warning(f"Failed to analyze project context: {e}")

        return context


class AIClient:
    """Client for AI API interactions"""

    def __init__(self, provider: str, config_manager: ConfigManager):
        self.provider = provider
        self.config = config_manager

        api_key = self.config.get_api_key(provider)
        if not api_key:
            raise ValueError(
                f"{provider.upper()}_API_KEY not found in config or environment"
            )

        if provider == "anthropic":
            self.client = Anthropic(api_key=api_key)
            self.model = self.config.get_model("anthropic")

        elif provider == "openai":
            self.client = openai.OpenAI(api_key=api_key)
            self.model = self.config.get_model("openai")

        elif provider == "openrouter":
            self.client = openai.OpenAI(
                api_key=api_key, base_url="https://openrouter.ai/api/v1"
            )
            self.model = self.config.get_model("openrouter")

        else:
            raise ValueError(
                f"Unsupported provider: {provider}. Use 'anthropic', 'openai', or 'openrouter'"
            )

    def analyze_context(
        self,
        session_context: SessionContext,
        scrollback_analysis: Dict,
        project_analysis: Dict,
    ) -> str:
        """Send context to AI for analysis and suggestions"""

        # Build prompt
        prompt = self._build_analysis_prompt(
            session_context, scrollback_analysis, project_analysis
        )

        try:
            if self.provider == "anthropic":
                response = self.client.messages.create(
                    model=self.model,
                    max_tokens=1000,
                    messages=[{"role": "user", "content": prompt}],
                )
                return response.content[0].text

            elif self.provider in ["openai", "openrouter"]:
                response = self.client.chat.completions.create(
                    model=self.model,
                    max_tokens=1000,
                    messages=[{"role": "user", "content": prompt}],
                )
                return response.choices[0].message.content

        except Exception as e:
            logger.error(f"AI API call failed: {e}")
            return f"Analysis unavailable: {str(e)}"

    def _build_analysis_prompt(
        self,
        session_context: SessionContext,
        scrollback_analysis: Dict,
        project_analysis: Dict,
    ) -> str:
        """Build prompt for AI analysis"""

        prompt = f"""You are Muxgeist, a helpful AI assistant that lives in a terminal environment. 
Analyze this tmux session context and provide insights and suggestions.

CONTEXT:
- Session: {session_context.session_id}
- Current Directory: {session_context.cwd}
- Project Type: {project_analysis.get('project_type', 'unknown')}
- Working On: {scrollback_analysis.get('working_on', 'unknown')}
- User Sentiment: {scrollback_analysis.get('sentiment', 'neutral')}

RECENT ACTIVITY:
- Tools Detected: {', '.join(scrollback_analysis.get('tools_detected', []))}
- Recent Commands: {scrollback_analysis.get('recent_commands', [])[-3:]}

ISSUES DETECTED:
{scrollback_analysis.get('errors_found', [])}

Please provide:
1. A brief assessment of what the user is doing
2. 2-3 specific, actionable suggestions
3. Any potential issues or improvements

Keep responses concise and terminal-friendly. Focus on being helpful, not verbose.
"""
        return prompt


class MuxgeistAI:
    """Main AI service for Muxgeist"""

    def __init__(self, ai_provider: str = None):
        self.config = ConfigManager()
        self.daemon_client = DaemonClient(self.config)
        self.context_analyzer = ContextAnalyzer()

        # Auto-detect provider if not specified
        if ai_provider is None:
            ai_provider = self._detect_provider()

        self.ai_client = AIClient(ai_provider, self.config)
        logger.info(
            f"Initialized with {ai_provider} provider using model: {self.ai_client.model}"
        )

    def _detect_provider(self) -> str:
        """Auto-detect available AI provider"""
        # Check config file first, then environment variables
        providers = ["anthropic", "openai", "openrouter"]

        for provider in providers:
            if self.config.get_api_key(provider):
                return provider

        # Default to anthropic, will fail gracefully if no key
        return "anthropic"

    def analyze_session(self, session_id: str) -> Optional[AnalysisResult]:
        """Perform complete analysis of a session"""

        # Get context from daemon
        context = self.daemon_client.get_context(session_id)
        if not context:
            logger.error(f"Failed to get context for session: {session_id}")
            return None

        # Analyze scrollback and project
        scrollback_analysis = self.context_analyzer.analyze_scrollback(
            context.scrollback
        )
        project_analysis = self.context_analyzer.analyze_project_context(context.cwd)

        # Get AI analysis
        ai_response = self.ai_client.analyze_context(
            context, scrollback_analysis, project_analysis
        )

        # Extract suggestions (simple parsing)
        suggestions = []
        lines = ai_response.split("\n")
        for line in lines:
            if any(
                marker in line.lower()
                for marker in ["suggestion", "recommend", "try", "1.", "2.", "3."]
            ):
                suggestions.append(line.strip())

        # Determine if requires attention
        requires_attention = (
            len(scrollback_analysis.get("errors_found", [])) > 0
            or scrollback_analysis.get("sentiment") == "frustrated"
        )

        # Calculate confidence (simple heuristic)
        confidence = 0.8 if scrollback_analysis.get("tools_detected") else 0.5

        return AnalysisResult(
            session_context=context,
            analysis=ai_response,
            suggestions=suggestions[:3],  # Limit to 3 suggestions
            confidence=confidence,
            requires_attention=requires_attention,
        )

    def get_session_summary(self) -> str:
        """Get summary of all tracked sessions"""
        sessions = self.daemon_client.list_sessions()
        if not sessions:
            return "No active tmux sessions found."

        summary = f"Tracking {len(sessions)} session(s):\n"
        for session in sessions:
            context = self.daemon_client.get_context(session)
            if context:
                summary += f"  • {session}: {context.cwd}\n"

        return summary.strip()


def main():
    """Test the AI service"""
    if len(sys.argv) < 2:
        print(
            "Usage: python3 muxgeist_ai.py <session_name> [--provider anthropic|openai|openrouter]"
        )
        print(
            "       python3 muxgeist_ai.py --list [--provider anthropic|openai|openrouter]"
        )
        print("       python3 muxgeist_ai.py --providers")
        print("       python3 muxgeist_ai.py --config")
        sys.exit(1)

    # Parse arguments
    provider = None
    if "--provider" in sys.argv:
        provider_index = sys.argv.index("--provider")
        if provider_index + 1 < len(sys.argv):
            provider = sys.argv[provider_index + 1]
            # Remove provider args from sys.argv for simpler processing
            sys.argv.pop(provider_index + 1)
            sys.argv.pop(provider_index)

    try:
        # Handle special commands
        if sys.argv[1] == "--config":
            config = ConfigManager()
            print(f"Configuration file: {config.config_file}")
            print(f"Config directory: {config.config_dir}")
            if config.config_file.exists():
                print("✓ Config file exists")
            else:
                print("⚠ Config file not found, will be created")

            # Show current configuration
            print("\nCurrent configuration:")
            for provider_name in ["anthropic", "openai", "openrouter"]:
                api_key = config.get_api_key(provider_name)
                if api_key:
                    print(f"  ✓ {provider_name}: API key configured")
                else:
                    print(f"  ✗ {provider_name}: No API key")
            return

        if sys.argv[1] == "--providers":
            config = ConfigManager()
            print("Available AI providers:")
            providers = []

            for provider_name in ["anthropic", "openai", "openrouter"]:
                api_key = config.get_api_key(provider_name)
                if api_key:
                    providers.append(f"✓ {provider_name}")
                else:
                    providers.append(f"✗ {provider_name} (no API key)")

            for p in providers:
                print(f"  {p}")
            return

        ai_service = MuxgeistAI(provider)

        if sys.argv[1] == "--list":
            print(ai_service.get_session_summary())
        else:
            session_name = sys.argv[1]
            result = ai_service.analyze_session(session_name)

            if result:
                print(
                    f"\n🌟 Muxgeist Analysis for '{session_name}' (via {ai_service.ai_client.provider})"
                )
                print("=" * 50)
                print(result.analysis)
                print(f"\nModel: {ai_service.ai_client.model}")
                print(f"Confidence: {result.confidence:.1%}")
                if result.requires_attention:
                    print("⚠️  Requires attention")
            else:
                print(f"Failed to analyze session: {session_name}")

    except Exception as e:
        logger.error(f"Error: {e}")
        print(f"\n❌ Error: {e}")

        # Provide helpful hints for common errors
        if "API key" in str(e):
            print("\n💡 Configuration help:")
            print(f"  Edit config file: nvim ~/.config/muxgeist/config.yaml")
            print("  Or set environment variables:")
            print("    export ANTHROPIC_API_KEY='your-key'")
            print("    export OPENAI_API_KEY='your-key'")
            print("    export OPENROUTER_API_KEY='your-key'")
            print("\nCheck config with: python3 muxgeist_ai.py --config")

        sys.exit(1)


if __name__ == "__main__":
    main()
