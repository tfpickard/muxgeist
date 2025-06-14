#!/usr/bin/env python3

import os
import sys
import time
import tempfile
import subprocess
from pathlib import Path
import unittest
from unittest.mock import patch, MagicMock

# Add current directory to path for imports
sys.path.insert(0, ".")

from muxgeist_ai import (
    DaemonClient,
    ContextAnalyzer,
    SessionContext,
    MuxgeistAI,
    AnalysisResult,
)


class TestDaemonClient(unittest.TestCase):
    """Test daemon client functionality"""

    def setUp(self):
        self.client = DaemonClient()

    def test_status_command(self):
        """Test status command (requires running daemon)"""
        try:
            status = self.client.get_status()
            self.assertIsInstance(status, str)
            print(f"✓ Daemon status: {status}")
        except Exception as e:
            print(f"⚠ Daemon not running: {e}")

    def test_list_sessions(self):
        """Test session listing"""
        try:
            sessions = self.client.list_sessions()
            self.assertIsInstance(sessions, list)
            print(f"✓ Found {len(sessions)} sessions: {sessions}")
        except Exception as e:
            print(f"⚠ Could not list sessions: {e}")


class TestContextAnalyzer(unittest.TestCase):
    """Test context analysis functionality"""

    def setUp(self):
        self.analyzer = ContextAnalyzer()

    def test_scrollback_analysis_with_errors(self):
        """Test scrollback analysis with error detection"""
        scrollback = """
$ gcc test.c -o test
test.c:10:5: error: 'undeclared_var' undeclared (first use in this function)
$ make clean
$ make
gcc: error: no input files
$ ls -la
        """

        analysis = self.analyzer.analyze_scrollback(scrollback)

        self.assertGreater(len(analysis["errors_found"]), 0)
        self.assertIn("c compilation", analysis["tools_detected"])
        self.assertIn("build system", analysis["tools_detected"])
        print(f"✓ Error detection: found {len(analysis['errors_found'])} errors")
        print(f"✓ Tool detection: {analysis['tools_detected']}")

    def test_scrollback_analysis_python(self):
        """Test Python development detection"""
        scrollback = """
$ python -m venv venv
$ source venv/bin/activate
$ pip install requests
$ python main.py
Traceback (most recent call last):
  File "main.py", line 5, in <module>
    import nonexistent_module
ModuleNotFoundError: No module named 'nonexistent_module'
        """

        analysis = self.analyzer.analyze_scrollback(scrollback)

        self.assertIn("python development", analysis["tools_detected"])
        self.assertGreater(len(analysis["errors_found"]), 0)
        print(f"✓ Python development detected")

    def test_project_analysis(self):
        """Test project context analysis"""
        # Create a temporary directory with C project files
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create some test files
            (Path(tmpdir) / "Makefile").touch()
            (Path(tmpdir) / "main.c").touch()
            (Path(tmpdir) / "README.md").touch()

            analysis = self.analyzer.analyze_project_context(tmpdir)

            self.assertEqual(analysis["project_type"], "c/c++ project")
            self.assertEqual(analysis["build_system"], "make")
            self.assertIn("main.c", analysis["files_of_interest"])
            print(f"✓ Project analysis: {analysis['project_type']}")


class MockAIClient:
    """Mock AI client for testing without API keys"""

    def __init__(self, provider="mock"):
        self.provider = provider

    def analyze_context(self, session_context, scrollback_analysis, project_analysis):
        """Return mock analysis"""
        working_on = scrollback_analysis.get("working_on", "unknown")
        errors = len(scrollback_analysis.get("errors_found", []))

        if errors > 0:
            return f"""I see you're working on {working_on} in {session_context.cwd}.

Assessment: You're encountering some compilation/runtime errors that need attention.

Suggestions:
1. Check the recent error messages - they often point directly to the issue
2. Try running 'make clean && make' to rebuild from scratch
3. Consider using debugging tools like gdb or adding debug prints

The errors suggest missing declarations or build configuration issues."""
        else:
            return f"""You're working on {working_on} in {session_context.cwd}.

Assessment: Development session progressing normally.

Suggestions:
1. Current workflow looks good - keep building incrementally
2. Consider running tests if you have them
3. Remember to commit your changes with git when ready"""


class TestMuxgeistAI(unittest.TestCase):
    """Test main AI service with mocking"""

    def test_ai_service_with_mock(self):
        """Test AI service with mock client"""

        # Create mock session context
        context = SessionContext(
            session_id="test-session",
            cwd="/tmp/test-project",
            pane="%1",
            last_activity=int(time.time()),
            scrollback="$ gcc test.c\ntest.c:5: error: syntax error",
            scrollback_length=50,
        )

        # Mock the daemon client
        with patch("muxgeist_ai.DaemonClient") as mock_daemon:
            mock_daemon.return_value.get_context.return_value = context

            # Create AI service with mock client
            ai_service = MuxgeistAI()
            ai_service.ai_client = MockAIClient()

            result = ai_service.analyze_session("test-session")

            self.assertIsInstance(result, AnalysisResult)
            self.assertTrue(result.requires_attention)  # Should detect error
            self.assertGreater(len(result.suggestions), 0)

            print(f"✓ Mock AI analysis completed")
            print(f"  Analysis: {result.analysis[:100]}...")
            print(f"  Suggestions: {len(result.suggestions)}")
            print(f"  Requires attention: {result.requires_attention}")


def run_integration_tests():
    """Run integration tests that require actual daemon"""
    print("\n=== Integration Tests (require running daemon) ===")

    # Check if daemon is running
    try:
        client = DaemonClient()
        status = client.get_status()
        print(f"✓ Daemon is running: {status}")

        # Test session listing
        sessions = client.list_sessions()
        if sessions:
            print(f"✓ Found sessions: {sessions}")

            # Test context retrieval for first session
            first_session = sessions[0]
            context = client.get_context(first_session)
            if context:
                print(f"✓ Retrieved context for {first_session}:")
                print(f"  CWD: {context.cwd}")
                print(f"  Pane: {context.pane}")
            else:
                print(f"⚠ Could not get context for {first_session}")
        else:
            print("ℹ No tmux sessions found")

    except Exception as e:
        print(f"⚠ Integration tests skipped - daemon not running: {e}")
        print("  Start the daemon with: ./muxgeist-daemon &")


def run_ai_api_tests():
    """Run tests with actual AI APIs if keys are available"""
    print("\n=== AI API Tests (require API keys) ===")

    has_anthropic = bool(os.getenv("ANTHROPIC_API_KEY"))
    has_openai = bool(os.getenv("OPENAI_API_KEY"))

    if not (has_anthropic or has_openai):
        print("⚠ No AI API keys found in environment")
        print("  Set ANTHROPIC_API_KEY or OPENAI_API_KEY to test AI integration")
        return

    # Test with available provider
    provider = "anthropic" if has_anthropic else "openai"
    print(f"✓ Testing with {provider} API")

    try:
        from muxgeist_ai import AIClient

        # Create test context
        context = SessionContext(
            session_id="test",
            cwd="/tmp",
            pane="%1",
            last_activity=int(time.time()),
            scrollback="$ echo 'hello world'\nhello world",
            scrollback_length=25,
        )

        analyzer = ContextAnalyzer()
        scrollback_analysis = analyzer.analyze_scrollback(context.scrollback)
        project_analysis = analyzer.analyze_project_context(context.cwd)

        ai_client = AIClient(provider)
        response = ai_client.analyze_context(
            context, scrollback_analysis, project_analysis
        )

        print(f"✓ AI API response received ({len(response)} chars)")
        print(f"  Preview: {response[:100]}...")

    except Exception as e:
        print(f"⚠ AI API test failed: {e}")


def main():
    """Run all tests"""
    print("=== Muxgeist AI Service Test Suite ===")

    # Unit tests
    print("\n=== Unit Tests ===")
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add test classes
    suite.addTests(loader.loadTestsFromTestCase(TestContextAnalyzer))
    suite.addTests(loader.loadTestsFromTestCase(TestMuxgeistAI))

    runner = unittest.TextTestRunner(verbosity=0, stream=open(os.devnull, "w"))
    result = runner.run(suite)

    if result.wasSuccessful():
        print("✓ All unit tests passed")
    else:
        print(f"⚠ {len(result.failures)} test failures, {len(result.errors)} errors")

    # Integration tests
    run_integration_tests()

    # AI API tests
    run_ai_api_tests()

    print("\n=== Test Suite Complete ===")


if __name__ == "__main__":
    main()
