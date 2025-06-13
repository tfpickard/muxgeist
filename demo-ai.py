#!/usr/bin/env python3

import os
import sys
import time
from pathlib import Path

# Add current directory to path
sys.path.insert(0, ".")

from muxgeist_ai import MuxgeistAI, SessionContext, ContextAnalyzer


def demo_context_analysis():
    """Demonstrate context analysis capabilities"""
    print("🔍 Context Analysis Demo")
    print("=" * 40)

    analyzer = ContextAnalyzer()

    # Demo 1: C compilation errors
    print("\n📝 Demo 1: C Compilation Session")
    scrollback1 = """
$ cd /home/user/my-project
$ ls
main.c  Makefile  README.md
$ make
gcc -Wall -g -o main main.c
main.c: In function 'main':
main.c:15:5: error: 'undeclared_variable' undeclared (first use in this function)
     undeclared_variable = 42;
     ^~~~~~~~~~~~~~~~~~~
main.c:15:5: note: each undeclared identifier is reported only once for each function it appears in
make: *** [Makefile:2: main] Error 1
$ nvim main.c
"""

    analysis1 = analyzer.analyze_scrollback(scrollback1)
    print(f"Tools detected: {analysis1['tools_detected']}")
    print(f"Errors found: {len(analysis1['errors_found'])}")
    print(f"Working on: {analysis1['working_on']}")
    print(f"Sentiment: {analysis1['sentiment']}")

    # Demo 2: Python development
    print("\n📝 Demo 2: Python Development Session")
    scrollback2 = """
$ python3 -m venv venv
$ source venv/bin/activate
(venv) $ pip install requests pandas
Successfully installed requests-2.28.0 pandas-1.5.0
(venv) $ python data_analyzer.py
Processing dataset...
✓ Loaded 1000 records
✓ Analysis complete
Results saved to output.csv
$ git add .
$ git commit -m "Add data analysis script"
"""

    analysis2 = analyzer.analyze_scrollback(scrollback2)
    print(f"Tools detected: {analysis2['tools_detected']}")
    print(f"Errors found: {len(analysis2['errors_found'])}")
    print(f"Working on: {analysis2['working_on']}")
    print(f"Sentiment: {analysis2['sentiment']}")


def demo_project_analysis():
    """Demonstrate project analysis"""
    print("\n🏗️  Project Analysis Demo")
    print("=" * 40)

    analyzer = ContextAnalyzer()

    # Get current directory analysis
    cwd = os.getcwd()
    analysis = analyzer.analyze_project_context(cwd)

    print(f"Current directory: {cwd}")
    print(f"Project type: {analysis['project_type']}")
    print(f"Build system: {analysis['build_system']}")
    print(f"Files of interest: {analysis['files_of_interest'][:5]}")  # Show first 5


def demo_mock_ai_analysis():
    """Demonstrate AI analysis with mock data"""
    print("\n🤖 AI Analysis Demo (Mock)")
    print("=" * 40)

    # Create realistic session context
    context = SessionContext(
        session_id="demo-session",
        cwd="/home/user/muxgeist",
        pane="%0",
        last_activity=int(time.time()),
        scrollback="""
$ make clean
rm -f muxgeist-daemon muxgeist-client
$ make
gcc -Wall -Wextra -std=c99 -pedantic -g -O2 -o muxgeist-daemon muxgeist-daemon.c
gcc -Wall -Wextra -std=c99 -pedantic -g -O2 -o muxgeist-client muxgeist-client.c
$ ./muxgeist-daemon &
[1] 12345
Starting Muxgeist daemon...
Muxgeist daemon listening on /tmp/muxgeist.sock
$ ./muxgeist-client status
OK: 2 sessions tracked
$ python3 muxgeist_ai.py --list
Tracking 2 session(s):
  • main: /home/user/muxgeist
  • dev: /home/user/projects/webapp
""",
        scrollback_length=450,
    )

    # Use the mock AI client from our test suite
    from test_ai_service import MockAIClient

    analyzer = ContextAnalyzer()
    scrollback_analysis = analyzer.analyze_scrollback(context.scrollback)
    project_analysis = analyzer.analyze_project_context(context.cwd)

    mock_ai = MockAIClient()
    response = mock_ai.analyze_context(context, scrollback_analysis, project_analysis)

    print("📊 Analysis Result:")
    print("-" * 20)
    print(response)
    print()
    print(f"📈 Detected Activity:")
    print(f"  Tools: {', '.join(scrollback_analysis['tools_detected'])}")
    print(f"  Project: {project_analysis['project_type']}")
    print(f"  Recent commands: {len(scrollback_analysis['recent_commands'])}")


def demo_live_integration():
    """Demonstrate live integration with daemon if available"""
    print("\n🔗 Live Integration Demo")
    print("=" * 40)

    try:
        from muxgeist_ai import DaemonClient

        client = DaemonClient()
        status = client.get_status()
        print(f"✓ Daemon status: {status}")

        sessions = client.list_sessions()
        print(f"✓ Found {len(sessions)} active sessions")

        if sessions:
            # Analyze first session
            session_name = sessions[0]
            print(f"\n📋 Analyzing session: {session_name}")

            context = client.get_context(session_name)
            if context:
                print(f"  CWD: {context.cwd}")
                print(f"  Last activity: {time.ctime(context.last_activity)}")
                print(f"  Scrollback length: {context.scrollback_length}")
            else:
                print("  ⚠ Could not retrieve context")
        else:
            print("  ℹ No active tmux sessions found")
            print("  Create a session with: tmux new-session -d -s demo")

    except Exception as e:
        print(f"⚠ Daemon not available: {e}")
        print("  Start daemon with: ./muxgeist-daemon &")


def main():
    """Run all demos"""
    print("🌟 Muxgeist AI Service Demo")
    print("=" * 50)

    try:
        demo_context_analysis()
        demo_project_analysis()
        demo_mock_ai_analysis()
        demo_live_integration()

        print("\n" + "=" * 50)
        print("🎉 Demo complete!")
        print("\nTo test with real AI:")
        print("  1. Set ANTHROPIC_API_KEY or OPENAI_API_KEY")
        print("  2. Start daemon: ./muxgeist-daemon &")
        print("  3. Run: python3 muxgeist_ai.py <session-name>")

    except KeyboardInterrupt:
        print("\n\n👋 Demo interrupted")
    except Exception as e:
        print(f"\n❌ Demo failed: {e}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
