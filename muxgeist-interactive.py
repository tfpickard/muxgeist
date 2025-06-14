#!/usr/bin/env python
import os
import sys
import time
import signal
import subprocess
import threading
import traceback
from datetime import datetime
from pathlib import Path

# Add current directory to path
sys.path.insert(0, str(Path(__file__).parent))

# Set up logging to file for debugging
import logging

log_file = Path.home() / ".config" / "muxgeist" / "interactive.log"
log_file.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.FileHandler(log_file), logging.StreamHandler(sys.stderr)],
)
logger = logging.getLogger(__name__)

logger.info("Starting muxgeist-interactive.py")

try:
    from muxgeist_ai import MuxgeistAI, DaemonClient

    logger.info("Successfully imported muxgeist_ai modules")
except ImportError as e:
    logger.error(f"Failed to import muxgeist_ai: {e}")
    print(f"❌ Import error: {e}")
    print("Make sure you're in the muxgeist directory and dependencies are installed")
    print(f"Log file: {log_file}")
    sys.exit(1)


class MuxgeistInteractive:
    """Interactive Muxgeist interface for tmux pane"""

    def __init__(self):
        logger.info("Initializing MuxgeistInteractive")
        self.running = True
        self.session_name = None
        self.ai_service = None
        self.last_analysis = None
        self.analysis_time = None

        # Setup signal handling
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

        # Get current tmux session
        self._detect_session()

        # Initialize AI service
        self._init_ai_service()

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        logger.info(f"Received signal {signum}")
        self.running = False
        print("\n👋 Muxgeist signing off...")
        sys.exit(0)

    def _detect_session(self):
        """Detect current tmux session"""
        try:
            result = subprocess.run(
                ["tmux", "display-message", "-p", "#{session_name}"],
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                self.session_name = result.stdout.strip()
                logger.info(f"Detected tmux session: {self.session_name}")
            else:
                self.session_name = "unknown"
                logger.warning(f"Failed to detect session: {result.stderr}")
        except Exception as e:
            self.session_name = "unknown"
            logger.error(f"Exception detecting session: {e}")

    def _init_ai_service(self):
        """Initialize AI service with error handling"""
        try:
            logger.info("Initializing AI service...")
            self.ai_service = MuxgeistAI()
            logger.info(
                f"AI service initialized with provider: {self.ai_service.ai_client.provider}"
            )
        except Exception as e:
            logger.error(f"Failed to initialize AI service: {e}")
            logger.error(f"Exception details: {traceback.format_exc()}")
            print(f"⚠️  AI service unavailable: {e}")
            self.ai_service = None

    def _clear_screen(self):
        """Clear the screen"""
        print("\033[2J\033[H", end="")

    def _get_terminal_size(self):
        """Get terminal dimensions"""
        try:
            result = subprocess.run(["stty", "size"], capture_output=True, text=True)
            if result.returncode == 0:
                rows, cols = result.stdout.strip().split()
                return int(rows), int(cols)
        except:
            pass
        return 24, 80  # Default size

    def _format_header(self):
        """Format the Muxgeist header"""
        rows, cols = self._get_terminal_size()

        # ASCII art logo (simplified for space)
        logo = "🌟 MUXGEIST"
        session_info = f"Session: {self.session_name}"
        timestamp = datetime.now().strftime("%H:%M:%S")

        # Center the header
        header_line = f"{logo} │ {session_info} │ {timestamp}"
        padding = max(0, (cols - len(header_line)) // 2)

        print("═" * cols)
        print(" " * padding + header_line)
        print("═" * cols)

    def _analyze_current_session(self):
        """Analyze current session context"""
        if not self.ai_service:
            return "AI service not available"

        try:
            logger.info(f"Analyzing session: {self.session_name}")
            print("🔍 Analyzing your session...")
            result = self.ai_service.analyze_session(self.session_name)

            if result:
                self.last_analysis = result
                self.analysis_time = datetime.now()
                logger.info("Analysis completed successfully")
                return result.analysis
            else:
                logger.warning("Analysis returned no result")
                return "Could not analyze session - no context available"

        except Exception as e:
            logger.error(f"Analysis failed: {e}")
            logger.error(f"Exception details: {traceback.format_exc()}")
            return f"Analysis failed: {e}"

    def _show_analysis(self):
        """Display the current analysis"""
        if not self.last_analysis:
            analysis = self._analyze_current_session()
            if isinstance(analysis, str):
                print(analysis)
                return

        result = self.last_analysis
        age_mins = (
            (datetime.now() - self.analysis_time).seconds // 60
            if self.analysis_time
            else 0
        )

        print(f"📊 Analysis Results (updated {age_mins}m ago):")
        print(
            f"🎯 Analyzing pane {result.session_context.pane} in session '{result.session_context.session_id}'"
        )
        print("─" * 50)
        print(result.analysis)

        if result.suggestions:
            print("\n💡 Suggestions:")
            for i, suggestion in enumerate(result.suggestions, 1):
                print(f"  {i}. {suggestion}")

        print(f"\n📈 Confidence: {result.confidence:.1%}")
        if result.requires_attention:
            print("⚠️  Requires attention")

        if self.ai_service:
            print(
                f"🤖 Provider: {self.ai_service.ai_client.provider} ({self.ai_service.ai_client.model})"
            )

    def _show_help(self):
        """Show help information"""
        print("🔧 Muxgeist Commands:")
        print("─" * 30)
        print("  a, analyze  - Analyze current session")
        print("  r, refresh  - Force refresh analysis")
        print("  s, status   - Show daemon status")
        print("  l, list     - List all sessions")
        print("  h, help     - Show this help")
        print("  d, debug    - Show debug information")
        print("  q, quit     - Dismiss Muxgeist")
        print("  <Enter>     - Re-analyze session")
        print()
        print("💡 Tips:")
        print("  • Muxgeist monitors your scrollback and context")
        print("  • Ask specific questions after analysis")
        print("  • Use 'q' to hide, then summon again anytime")

    def _show_status(self):
        """Show system status"""
        print("📊 System Status:")
        print("─" * 20)

        # Daemon status
        try:
            client = DaemonClient()
            status = client.get_status()
            print(f"✅ Daemon: {status}")
        except Exception as e:
            print(f"❌ Daemon: {e}")

        # AI service status
        if self.ai_service:
            print(f"✅ AI: {self.ai_service.ai_client.provider} ready")
        else:
            print("❌ AI: Not available")

        # Session info
        print(f"📱 Session: {self.session_name}")

        # Analysis status
        if self.last_analysis:
            age = datetime.now() - self.analysis_time
            print(f"🔍 Last analysis: {age.seconds}s ago")
        else:
            print("🔍 No analysis yet")

    def _show_debug(self):
        """Show debug information"""
        print("🐛 Debug Information:")
        print("─" * 25)
        print(f"Log file: {log_file}")
        print(f"Python path: {sys.path[0]}")
        print(f"Working directory: {os.getcwd()}")
        print(f"TMUX: {os.environ.get('TMUX', 'Not set')}")

        if self.ai_service:
            print(f"AI Provider: {self.ai_service.ai_client.provider}")
            print(f"AI Model: {self.ai_service.ai_client.model}")

        # Test daemon connection
        try:
            client = DaemonClient()
            sessions = client.list_sessions()
            print(f"Daemon sessions: {len(sessions)}")
        except Exception as e:
            print(f"Daemon error: {e}")

    def _list_sessions(self):
        """List all tracked sessions"""
        if not self.ai_service:
            print("AI service not available")
            return

        try:
            summary = self.ai_service.get_session_summary()
            print("📋 Tracked Sessions:")
            print("─" * 20)
            print(summary)
        except Exception as e:
            logger.error(f"Failed to list sessions: {e}")
            print(f"Failed to list sessions: {e}")

    def _handle_question(self, question):
        """Handle user questions about their context"""
        if not self.ai_service:
            print("AI service not available for questions")
            return

        # For now, just re-analyze with the question as context
        # In a more advanced version, we'd pass the question to the AI
        print(f"💬 Processing question: {question}")
        print("🔍 Let me analyze your current context...")

        analysis = self._analyze_current_session()
        if isinstance(analysis, str):
            print(analysis)
        else:
            self._show_analysis()

    def _get_user_input(self):
        """Get user input with prompt"""
        try:
            return input("\n🌟 muxgeist> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            return "q"

    def _process_command(self, cmd):
        """Process user command"""
        logger.debug(f"Processing command: {cmd}")

        if cmd in ("q", "quit", "exit"):
            return False
        elif cmd in ("a", "analyze", ""):
            self._show_analysis()
        elif cmd in ("r", "refresh"):
            self.last_analysis = None
            self._show_analysis()
        elif cmd in ("s", "status"):
            self._show_status()
        elif cmd in ("l", "list"):
            self._list_sessions()
        elif cmd in ("h", "help"):
            self._show_help()
        elif cmd in ("d", "debug"):
            self._show_debug()
        elif cmd.startswith("?") or len(cmd) > 10:  # Treat longer input as questions
            self._handle_question(cmd)
        else:
            print(f"Unknown command: {cmd}")
            print("Type 'h' for help or 'q' to quit")

        return True

    def run(self):
        """Main interactive loop"""
        logger.info("Starting interactive loop")

        try:
            self._clear_screen()
            self._format_header()

            print("👋 Welcome! I'm analyzing your session...")
            print()

            # Initial analysis
            self._show_analysis()

            # Interactive loop
            while self.running:
                try:
                    cmd = self._get_user_input()

                    if not self._process_command(cmd):
                        break

                except Exception as e:
                    logger.error(f"Error processing command: {e}")
                    print(f"Error: {e}")
                    continue

        except Exception as e:
            logger.error(f"Fatal error in run loop: {e}")
            logger.error(f"Exception details: {traceback.format_exc()}")
            print(f"❌ Fatal error: {e}")
            print(f"Check log file: {log_file}")

        # Clean exit
        logger.info("Exiting interactive mode")
        print("\n👋 Muxgeist dismissed. Use Ctrl+G to summon again!")


def main():
    """Entry point for interactive mode"""

    logger.info("Starting muxgeist-interactive main()")

    # Check if we're in tmux
    if not os.environ.get("TMUX"):
        error_msg = "❌ Muxgeist must run inside tmux"
        logger.error(error_msg)
        print(error_msg)
        print("Start tmux first: tmux new-session")
        sys.exit(1)

    # Check if daemon is running
    try:
        client = DaemonClient()
        status = client.get_status()
        logger.info(f"Daemon status: {status}")
    except Exception as e:
        error_msg = f"❌ Muxgeist daemon not running: {e}"
        logger.error(error_msg)
        print(error_msg)
        print("Start daemon: ./muxgeist-daemon &")
        print(f"Debug log: {log_file}")
        sys.exit(1)

    # Run interactive interface
    try:
        interface = MuxgeistInteractive()
        interface.run()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        print("\n👋 Goodbye!")
    except Exception as e:
        logger.error(f"Fatal error in main: {e}")
        logger.error(f"Exception details: {traceback.format_exc()}")
        print(f"❌ Error: {e}")
        print(f"Check log file: {log_file}")
        sys.exit(1)


if __name__ == "__main__":
    main()
