#!/bin/bash

# Multi-pane capture patch for Muxgeist
# This script updates the daemon and AI service to capture all panes in a session

set -e

echo "🔧 Applying multi-pane capture patch..."

# Check if we're on macOS (BSD sed) or Linux (GNU sed)
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE="sed -i ''"
else
    SED_INPLACE="sed -i"
fi

# Backup original files
echo "📋 Creating backups..."
cp muxgeist-daemon.c muxgeist-daemon.c.backup
cp muxgeist_ai.py muxgeist_ai.py.backup

echo "✅ Backups created (.backup files)"

# Apply daemon changes
echo "🔨 Patching daemon (muxgeist-daemon.c)..."

# 1. Increase buffer size for multi-pane content
$SED_INPLACE 's/#define MAX_BUFFER_SIZE 8192/#define MAX_BUFFER_SIZE 16384  \/\/ Increased for multi-pane content/' muxgeist-daemon.c

echo "✅ Updated buffer size"

# 2. Add the capture_all_panes function before update_session_context
cat >/tmp/capture_all_panes.c <<'EOF'
muxgeist_error_t capture_all_panes(session_context_t *session) {
  char cmd[512];
  char pane_list[2048];
  char temp_content[MAX_BUFFER_SIZE];
  
  // Clear existing scrollback
  session->scrollback[0] = '\0';
  session->scrollback_len = 0;

  // Get list of all panes in the session
  snprintf(cmd, sizeof(cmd), 
           "tmux list-panes -t %s -F '#{window_index}.#{pane_index}:#{pane_title}:#{pane_current_command}'", 
           session->session_id);
  
  if (execute_tmux_command(cmd, pane_list, sizeof(pane_list)) != ERROR_NONE) {
    return ERROR_TMUX_CMD;
  }

  // If no panes found, try to get content anyway
  if (strlen(pane_list) == 0) {
    snprintf(cmd, sizeof(cmd), "tmux capture-pane -t %s -p", session->session_id);
    FILE *fp = popen(cmd, "r");
    if (fp) {
      session->scrollback_len = fread(session->scrollback, 1, 
                                    sizeof(session->scrollback) - 1, fp);
      session->scrollback[session->scrollback_len] = '\0';
      pclose(fp);
    }
    return ERROR_NONE;
  }

  // Process each pane
  char *line = strtok(pane_list, "\n");
  int pane_count = 0;
  
  while (line != NULL && session->scrollback_len < sizeof(session->scrollback) - 500) {
    char pane_id[32];
    char pane_title[64] = "shell";
    char pane_command[64] = "";
    
    // Parse pane info: "window.pane:title:command"
    char *colon1 = strchr(line, ':');
    if (colon1) {
      *colon1 = '\0';
      strncpy(pane_id, line, sizeof(pane_id) - 1);
      pane_id[sizeof(pane_id) - 1] = '\0';
      
      char *colon2 = strchr(colon1 + 1, ':');
      if (colon2) {
        *colon2 = '\0';
        strncpy(pane_title, colon1 + 1, sizeof(pane_title) - 1);
        strncpy(pane_command, colon2 + 1, sizeof(pane_command) - 1);
      } else {
        strncpy(pane_title, colon1 + 1, sizeof(pane_title) - 1);
      }
    } else {
      strncpy(pane_id, line, sizeof(pane_id) - 1);
    }

    // Skip the muxgeist pane itself
    if (strstr(pane_title, "muxgeist") != NULL) {
      line = strtok(NULL, "\n");
      continue;
    }

    // Capture this pane's content
    snprintf(cmd, sizeof(cmd), "tmux capture-pane -t %s:%s -p", 
             session->session_id, pane_id);
    
    FILE *fp = popen(cmd, "r");
    if (fp) {
      size_t content_len = fread(temp_content, 1, sizeof(temp_content) - 1, fp);
      temp_content[content_len] = '\0';
      pclose(fp);

      // Only include panes with meaningful content (skip empty/minimal panes)
      if (content_len > 10) {
        // Add pane header
        int header_len = snprintf(session->scrollback + session->scrollback_len,
                                sizeof(session->scrollback) - session->scrollback_len,
                                "\n=== PANE %s (%s) ===\n", pane_id, pane_title);
        
        if (header_len > 0 && session->scrollback_len + header_len < sizeof(session->scrollback)) {
          session->scrollback_len += header_len;
        }

        // Add pane content (limit to avoid overflow)
        size_t available_space = sizeof(session->scrollback) - session->scrollback_len - 1;
        size_t copy_len = (content_len < available_space) ? content_len : available_space;
        
        if (copy_len > 0) {
          memcpy(session->scrollback + session->scrollback_len, temp_content, copy_len);
          session->scrollback_len += copy_len;
          session->scrollback[session->scrollback_len] = '\0';
        }
        
        pane_count++;
      }
    }

    line = strtok(NULL, "\n");
  }

  // If we didn't capture any panes (all were empty/muxgeist), capture the active pane
  if (pane_count == 0) {
    snprintf(cmd, sizeof(cmd), "tmux capture-pane -t %s -p", session->session_id);
    FILE *fp = popen(cmd, "r");
    if (fp) {
      session->scrollback_len = fread(session->scrollback, 1, 
                                    sizeof(session->scrollback) - 1, fp);
      session->scrollback[session->scrollback_len] = '\0';
      pclose(fp);
    }
  }

  return ERROR_NONE;
}

EOF

# Find where to insert the new function (before update_session_context)
LINE_NUM=$(grep -n "muxgeist_error_t update_session_context" muxgeist-daemon.c | cut -d: -f1)
if [ -n "$LINE_NUM" ]; then
    # Insert the new function before update_session_context
    head -n $((LINE_NUM - 1)) muxgeist-daemon.c >/tmp/daemon_part1.c
    cat /tmp/capture_all_panes.c >/tmp/daemon_part2.c
    tail -n +$LINE_NUM muxgeist-daemon.c >/tmp/daemon_part3.c
    cat /tmp/daemon_part1.c /tmp/daemon_part2.c /tmp/daemon_part3.c >muxgeist-daemon.c
    rm /tmp/daemon_part*.c /tmp/capture_all_panes.c
    echo "✅ Added capture_all_panes function"
else
    echo "❌ Could not find update_session_context function"
    exit 1
fi

# 3. Update the update_session_context function to use capture_all_panes
# Create a simple Python script to do the replacement since sed is complex for multiline
python3 <<'EOF'
import re

with open('muxgeist-daemon.c', 'r') as f:
    content = f.read()

# Replace the scrollback capture section in update_session_context
old_pattern = r'// Capture scrollback\s*\n.*?snprintf\(cmd.*?tmux capture-pane.*?\n.*?FILE \*fp = popen.*?\n.*?if \(fp\) \{.*?\n.*?session->scrollback_len =.*?\n.*?session->scrollback\[session->scrollback_len\] = .*?\n.*?pclose\(fp\);.*?\n.*?\}'

new_code = '''  // Capture content from all panes
  rc = capture_all_panes(session);'''

content = re.sub(old_pattern, new_code, content, flags=re.DOTALL)

# Also update execute_tmux_command to read all output
old_exec_pattern = r'if \(fgets\(output, output_size, fp\) == NULL\) \{\s*\n.*?output\[0\] = \'\\0\';\s*\n.*?\}'

new_exec_code = '''// Read all output, not just first line
  size_t total_read = 0;
  while (total_read < output_size - 1) {
    size_t bytes_read = fread(output + total_read, 1, output_size - total_read - 1, fp);
    if (bytes_read == 0) break;
    total_read += bytes_read;
  }
  
  output[total_read] = '\\0';

  // Remove trailing newline if present
  if (total_read > 0 && output[total_read - 1] == '\\n') {
    output[total_read - 1] = '\\0';
  }'''

content = re.sub(old_exec_pattern, new_exec_code, content, flags=re.DOTALL)

with open('muxgeist-daemon.c', 'w') as f:
    f.write(content)

print("✅ Updated daemon scrollback capture logic")
EOF

echo "🔨 Patching AI service (muxgeist_ai.py)..."

# Add multi-pane parsing to ContextAnalyzer
python3 <<'EOF'
import re

# Read the file
with open('muxgeist_ai.py', 'r') as f:
    content = f.read()

# Check if already patched
if "parse_multi_pane_scrollback" in content:
    print("⚠️  AI service already appears to be patched")
    exit(0)

# Add the parse_multi_pane_scrollback method
new_method = '''    def parse_multi_pane_scrollback(self, scrollback: str) -> Dict[str, str]:
        """Parse multi-pane scrollback into individual pane contents"""
        panes = {}
        
        if "=== PANE" not in scrollback:
            # Single pane format
            panes["main"] = scrollback
            return panes
        
        # Split by pane headers
        sections = scrollback.split("=== PANE ")
        for section in sections[1:]:  # Skip first empty section
            lines = section.split("\\n", 1)
            if len(lines) >= 2:
                # Extract pane ID and title from header like "0.0 (shell) ==="
                header = lines[0].split(" ===")[0]
                pane_content = lines[1] if len(lines) > 1 else ""
                
                # Clean up header to get pane info
                pane_info = header.strip("()").replace("(", " - ")
                panes[pane_info] = pane_content
        
        return panes

'''

# Find the end of ContextAnalyzer.__init__ method
class_start = content.find('class ContextAnalyzer:')
if class_start == -1:
    print("❌ Could not find ContextAnalyzer class")
    exit(1)

init_start = content.find('def __init__(self):', class_start)
if init_start == -1:
    print("❌ Could not find ContextAnalyzer.__init__ method")
    exit(1)

# Find the end of the __init__ method (look for the closing bracket of the patterns list)
init_section = content[init_start:]
bracket_end = init_section.find('        ]')
if bracket_end == -1:
    print("❌ Could not find end of __init__ method")
    exit(1)

insert_pos = init_start + bracket_end + init_section[bracket_end:].find('\n') + 1
content = content[:insert_pos] + new_method + content[insert_pos:]

# Update analyze_scrollback method
old_analyze_start = content.find('def analyze_scrollback(self, scrollback: str) -> Dict[str, any]:')
if old_analyze_start == -1:
    print("❌ Could not find analyze_scrollback method")
    exit(1)

# Find the analysis dict initialization
analysis_dict_start = content.find('analysis = {', old_analyze_start)
analysis_dict_end = content.find('}', analysis_dict_start) + 1

old_analysis_dict = content[analysis_dict_start:analysis_dict_end]
new_analysis_dict = '''analysis = {
            "errors_found": [],
            "tools_detected": [],
            "recent_commands": [],
            "working_on": "unknown",
            "sentiment": "neutral",
            "panes_analyzed": [],
            "primary_activity": "unknown",
        }'''

content = content.replace(old_analysis_dict, new_analysis_dict)

# Replace the scrollback processing section
old_processing = '''        lines = scrollback.split("\\n")
        recent_lines = lines[-50:]  # Look at last 50 lines'''

new_processing = '''        # Parse multi-pane content
        panes = self.parse_multi_pane_scrollback(scrollback)
        analysis["panes_analyzed"] = list(panes.keys())

        # Analyze each pane
        all_lines = []
        for pane_id, pane_content in panes.items():
            lines = pane_content.split("\\n")
            all_lines.extend(lines)
            
            # Track which pane has the most activity
            if len(lines) > 10:  # Significant content
                analysis["primary_activity"] = pane_id

        # Use recent lines from all panes for analysis
        recent_lines = all_lines[-100:]  # Increased for multi-pane'''

content = content.replace(old_processing, new_processing)

# Update working_on detection to include multi-pane info
working_section_start = content.find('# Determine what user is working on')
working_section_end = content.find('# Simple sentiment analysis', working_section_start)

if working_section_start != -1 and working_section_end != -1:
    working_section = content[working_section_start:working_section_end]
    
    # Add multi-pane context
    enhanced_working = working_section + '''        # Enhanced working context for multi-pane
        if len(panes) > 1:
            analysis["working_on"] += f" (across {len(panes)} panes)"

        '''
    
    content = content[:working_section_start] + enhanced_working + content[working_section_end:]

# Update the AI prompt in _build_analysis_prompt
prompt_method_start = content.find('def _build_analysis_prompt(')
if prompt_method_start != -1:
    prompt_start = content.find('prompt = f"""', prompt_method_start)
    if prompt_start != -1:
        # Insert pane info before the prompt
        pane_info_code = '''        # Get pane information
        panes_info = ""
        if "panes_analyzed" in scrollback_analysis:
            panes = scrollback_analysis["panes_analyzed"]
            if len(panes) > 1:
                panes_info = f"- Active Panes: {', '.join(panes)}\\n"
                if "primary_activity" in scrollback_analysis:
                    panes_info += f"- Primary Activity Pane: {scrollback_analysis['primary_activity']}\\n"

        '''
        content = content[:prompt_start] + pane_info_code + content[prompt_start:]
        
        # Update the prompt to include pane info
        content = content.replace(
            '- User Sentiment: {scrollback_analysis.get(\'sentiment\', \'neutral\')}',
            '- User Sentiment: {scrollback_analysis.get(\'sentiment\', \'neutral\')}\n{panes_info}'
        )
        
        # Update the prompt instructions
        content = content.replace(
            'Keep responses concise and terminal-friendly. Focus on being helpful, not verbose.',
            'Keep responses concise and terminal-friendly. Focus on being helpful, not verbose.\nIf analyzing multiple panes, provide context-aware suggestions that consider the user\'s multi-tasking workflow.'
        )

# Write the updated file
with open('muxgeist_ai.py', 'w') as f:
    f.write(content)

print("✅ Updated AI service for multi-pane support")
EOF

echo "🔧 Rebuilding daemon..."
make clean && make

echo ""
echo "✅ Multi-pane capture patch applied successfully!"
echo ""
echo "Changes made:"
echo "  • Daemon now captures content from all panes in each session"
echo "  • Skips the muxgeist pane itself to avoid recursion"
echo "  • AI service parses multi-pane content intelligently"
echo "  • Enhanced context analysis across multiple panes"
echo "  • Improved AI prompts for multi-pane workflows"
echo ""
echo "To test:"
echo "  1. Restart daemon: pkill muxgeist-daemon && ./muxgeist-daemon &"
echo "  2. Create multiple panes: tmux split-window"
echo "  3. Test analysis: python3 muxgeist_ai.py <session-name>"
echo ""
echo "Backups saved as .backup files"
