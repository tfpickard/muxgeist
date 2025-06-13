#!/usr/bin/env python3

import os
import sys
import subprocess
import socket
from pathlib import Path

# Add current directory to path
sys.path.insert(0, ".")


def check_daemon():
    """Check if daemon is running and responding"""
    print("🔧 Checking Muxgeist daemon...")

    socket_path = "/tmp/muxgeist.sock"
    if not Path(socket_path).exists():
        print("❌ Daemon socket not found")
        print("   Start daemon with: ./muxgeist-daemon &")
        return False

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(socket_path)
        sock.send(b"status")
        response = sock.recv(1024).decode()
        sock.close()

        print(f"✅ Daemon responding: {response}")
        return True
    except Exception as e:
        print(f"❌ Daemon connection failed: {e}")
        return False


def check_tmux():
    """Check tmux sessions"""
    print("\n🔧 Checking tmux sessions...")

    try:
        result = subprocess.run(
            ["tmux", "list-sessions"], capture_output=True, text=True
        )
        if result.returncode == 0:
            sessions = result.stdout.strip().split("\n")
            print(f"✅ Found {len(sessions)} tmux sessions:")
            for session in sessions:
                print(f"   {session}")
            return sessions
        else:
            print("❌ No tmux sessions found")
            print("   Create one with: tmux new-session -d -s test")
            return []
    except FileNotFoundError:
        print("❌ tmux not found - please install tmux")
        return []


def check_api_keys():
    """Check AI API key configuration"""
    print("\n🔧 Checking AI API keys...")

    providers = []
    if os.getenv("ANTHROPIC_API_KEY"):
        providers.append("✅ Anthropic")
    else:
        providers.append("❌ Anthropic (missing ANTHROPIC_API_KEY)")

    if os.getenv("OPENAI_API_KEY"):
        providers.append("✅ OpenAI")
    else:
        providers.append("❌ OpenAI (missing OPENAI_API_KEY)")

    if os.getenv("OPENROUTER_API_KEY"):
        providers.append("✅ OpenRouter")
    else:
        providers.append("❌ OpenRouter (missing OPENROUTER_API_KEY)")

    for provider in providers:
        print(f"   {provider}")

    has_key = any("✅" in p for p in providers)
    if not has_key:
        print("\n💡 Set an API key to enable AI features:")
        print("   export ANTHROPIC_API_KEY='your-key'")
        print("   export OPENROUTER_API_KEY='your-key'")
        print("   export OPENAI_API_KEY='your-key'")

    return has_key


def test_context_capture(session_name):
    """Test context capture for a specific session"""
    print(f"\n🔧 Testing context capture for session: {session_name}")

    try:
        from muxgeist_ai import DaemonClient

        client = DaemonClient()
        context = client.get_context(session_name)

        if context:
            print(f"✅ Context retrieved:")
            print(f"   Session: {context.session_id}")
            print(f"   CWD: {context.cwd}")
            print(f"   Pane: {context.pane}")
            print(f"   Scrollback length: {context.scrollback_length}")
            print(f"   Scrollback preview: {repr(context.scrollback[:100])}")

            if context.scrollback:
                print("✅ Scrollback captured successfully")
            else:
                print("⚠️  Scrollback empty - trying direct tmux capture...")

                # Try direct tmux capture
                result = subprocess.run(
                    ["tmux", "capture-pane", "-t", session_name, "-p"],
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0:
                    print(f"✅ Direct tmux capture works ({len(result.stdout)} chars)")
                    print(f"   Preview: {repr(result.stdout[:100])}")
                else:
                    print(f"❌ Direct tmux capture failed: {result.stderr}")

            return context
        else:
            print(f"❌ Could not get context for session: {session_name}")
            return None

    except Exception as e:
        print(f"❌ Context capture failed: {e}")
        return None


def test_ai_analysis(context):
    """Test AI analysis if context is available"""
    if not context:
        return

    print("\n🔧 Testing AI analysis...")

    try:
        from muxgeist_ai import ContextAnalyzer

        analyzer = ContextAnalyzer()
        scrollback_analysis = analyzer.analyze_scrollback(context.scrollback)

        print("✅ Context analysis completed:")
        print(f"   Tools detected: {scrollback_analysis['tools_detected']}")
        print(f"   Errors found: {len(scrollback_analysis['errors_found'])}")
        print(f"   Working on: {scrollback_analysis['working_on']}")
        print(f"   Sentiment: {scrollback_analysis['sentiment']}")

        # Test AI call if we have keys
        if check_api_keys():
            print("\n🤖 Testing AI API call...")
            try:
                from muxgeist_ai import MuxgeistAI

                ai_service = MuxgeistAI()
                result = ai_service.analyze_session(context.session_id)

                if result:
                    print(f"✅ AI analysis successful!")
                    print(f"   Provider: {ai_service.ai_client.provider}")
                    print(f"   Model: {ai_service.ai_client.model}")
                    print(f"   Response length: {len(result.analysis)} chars")
                    print(f"   Suggestions: {len(result.suggestions)}")
                else:
                    print("❌ AI analysis failed")

            except Exception as e:
                print(f"❌ AI analysis error: {e}")

    except Exception as e:
        print(f"❌ Analysis error: {e}")


def main():
    """Run comprehensive diagnostic"""
    print("🌟 Muxgeist Diagnostic Tool")
    print("=" * 40)

    # Check all components
    daemon_ok = check_daemon()
    sessions = check_tmux()
    api_keys_ok = check_api_keys()

    if daemon_ok and sessions:
        # Test with first session
        first_session = sessions[0].split(":")[0]  # Extract session name
        context = test_context_capture(first_session)
        test_ai_analysis(context)

    print("\n" + "=" * 40)
    print("🎯 Diagnostic Summary:")

    if daemon_ok:
        print("✅ Daemon is running")
    else:
        print("❌ Daemon needs to be started")

    if sessions:
        print(f"✅ Found {len(sessions)} tmux sessions")
    else:
        print("❌ No tmux sessions found")

    if api_keys_ok:
        print("✅ AI API keys configured")
    else:
        print("❌ No AI API keys found")

    if daemon_ok and sessions and api_keys_ok:
        print("\n🎉 Muxgeist should be fully functional!")
    else:
        print("\n🔧 Fix the issues above to use Muxgeist")


if __name__ == "__main__":
    main()
