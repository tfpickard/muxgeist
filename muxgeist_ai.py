#!/usr/bin/env python3

import socket
import json
import re
import os
import sys
import time
import logging
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path

import openai
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


class DaemonClient:
    """Client for communicating with muxgeist daemon"""

    def __init__(self, socket_path: str = "/tmp/muxgeist.sock"):
        self.socket_path = socket_path

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

        for line in lines:
            if ":" in line:
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

        # Get actual scrollback content (simplified for now)
        context_data["scrollback"] = ""  # TODO: Get from daemon

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

    def analyze_scrollback(self, scrollback: str) -> Dict[str, any]:
        """Analyze scrollback content for patterns and context"""
        analysis = {
            "errors_found": [],
            "tools_detected": [],
            "recent_commands": [],
            "working_on": "unknown",
            "sentiment": "neutral",
        }

        if not scrollback:
            return analysis

        lines = scrollback.split("\n")
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

    def __init__(self, provider: str = "anthropic"):
        self.provider = provider

        if provider == "anthropic":
            api_key = os.getenv("ANTHROPIC_API_KEY")
            if not api_key:
                raise ValueError("ANTHROPIC_API_KEY environment variable required")
            self.client = Anthropic(api_key=api_key)
        elif provider == "openai":
            api_key = os.getenv("OPENAI_API_KEY")
            if not api_key:
                raise ValueError("OPENAI_API_KEY environment variable required")
            self.client = openai.OpenAI(api_key=api_key)
        else:
            raise ValueError(f"Unsupported provider: {provider}")

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
                    model="claude-3-sonnet-20240229",
                    max_tokens=1000,
                    messages=[{"role": "user", "content": prompt}],
                )
                return response.content[0].text

            elif self.provider == "openai":
                response = self.client.chat.completions.create(
                    model="gpt-4",
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

    def __init__(self, ai_provider: str = "anthropic"):
        self.daemon_client = DaemonClient()
        self.context_analyzer = ContextAnalyzer()
        self.ai_client = AIClient(ai_provider)

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
    if len(sys.argv) != 2:
        print("Usage: python3 muxgeist_ai.py <session_name>")
        print("       python3 muxgeist_ai.py --list")
        sys.exit(1)

    try:
        ai_service = MuxgeistAI()

        if sys.argv[1] == "--list":
            print(ai_service.get_session_summary())
        else:
            session_name = sys.argv[1]
            result = ai_service.analyze_session(session_name)

            if result:
                print(f"\n🌟 Muxgeist Analysis for '{session_name}'")
                print("=" * 50)
                print(result.analysis)
                print(f"\nConfidence: {result.confidence:.1%}")
                if result.requires_attention:
                    print("⚠️  Requires attention")
            else:
                print(f"Failed to analyze session: {session_name}")

    except Exception as e:
        logger.error(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
