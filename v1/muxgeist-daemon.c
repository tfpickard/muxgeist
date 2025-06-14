#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define MUXGEIST_SOCKET_PATH "/tmp/muxgeist.sock"
#define MAX_SESSIONS 32
#define MAX_BUFFER_SIZE 16384 // Increased for multi-pane content
#define MAX_COMMAND_SIZE 512
#define CONTEXT_HISTORY_SIZE 100

typedef enum {
  ERROR_NONE = 0,
  ERROR_SOCKET_CREATE,
  ERROR_SOCKET_BIND,
  ERROR_SOCKET_LISTEN,
  ERROR_MEMORY_ALLOC,
  ERROR_TMUX_CMD,
  ERROR_FILE_IO,
  ERROR_INVALID_SESSION,
  ERROR_UNKNOWN = 255
} muxgeist_error_t;

typedef struct {
  char command[MAX_COMMAND_SIZE];
  char cwd[PATH_MAX];
  time_t timestamp;
  int exit_code;
} command_entry_t;

typedef struct {
  char session_id[64];
  char current_cwd[PATH_MAX];
  char current_pane[16];
  time_t last_activity;
  command_entry_t history[CONTEXT_HISTORY_SIZE];
  int history_count;
  int history_index;
  char scrollback[MAX_BUFFER_SIZE];
  int scrollback_len;
} session_context_t;

typedef struct {
  session_context_t sessions[MAX_SESSIONS];
  int session_count;
  int server_socket;
  volatile sig_atomic_t running;
} muxgeist_state_t;

static muxgeist_state_t g_state = {0};

void signal_handler(int sig) {
  printf("Received signal %d, shutting down...\n", sig);
  g_state.running = 0;
}

muxgeist_error_t setup_socket(void) {
  struct sockaddr_un addr;

  // Remove existing socket
  unlink(MUXGEIST_SOCKET_PATH);

  g_state.server_socket = socket(AF_UNIX, SOCK_STREAM, 0);
  if (g_state.server_socket == -1) {
    perror("socket");
    return ERROR_SOCKET_CREATE;
  }

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, MUXGEIST_SOCKET_PATH, sizeof(addr.sun_path) - 1);

  if (bind(g_state.server_socket, (struct sockaddr *)&addr, sizeof(addr)) ==
      -1) {
    perror("bind");
    close(g_state.server_socket);
    return ERROR_SOCKET_BIND;
  }

  if (listen(g_state.server_socket, 5) == -1) {
    perror("listen");
    close(g_state.server_socket);
    return ERROR_SOCKET_LISTEN;
  }

  printf("Muxgeist daemon listening on %s\n", MUXGEIST_SOCKET_PATH);
  return ERROR_NONE;
}

muxgeist_error_t execute_tmux_command(const char *cmd, char *output,
                                      size_t output_size) {
  FILE *fp = popen(cmd, "r");
  if (!fp) {
    return ERROR_TMUX_CMD;
  }

  // Read all output, not just first line
  size_t total_read = 0;
  while (total_read < output_size - 1) {
    size_t bytes_read =
        fread(output + total_read, 1, output_size - total_read - 1, fp);
    if (bytes_read == 0)
      break;
    total_read += bytes_read;
  }

  output[total_read] = '\0';

  // Remove trailing newline if present
  if (total_read > 0 && output[total_read - 1] == '\n') {
    output[total_read - 1] = '\0';
  }

  pclose(fp);
  return ERROR_NONE;
}

session_context_t *find_session(const char *session_id) {
  for (int i = 0; i < g_state.session_count; i++) {
    if (strcmp(g_state.sessions[i].session_id, session_id) == 0) {
      return &g_state.sessions[i];
    }
  }
  return NULL;
}

session_context_t *create_session(const char *session_id) {
  if (g_state.session_count >= MAX_SESSIONS) {
    return NULL;
  }

  session_context_t *session = &g_state.sessions[g_state.session_count];
  memset(session, 0, sizeof(session_context_t));

  strncpy(session->session_id, session_id, sizeof(session->session_id) - 1);
  session->last_activity = time(NULL);

  g_state.session_count++;
  return session;
}

muxgeist_error_t capture_all_panes(session_context_t *session) {
  char cmd[512];
  char pane_list[2048];
  char temp_content[MAX_BUFFER_SIZE];

  // Clear existing scrollback
  session->scrollback[0] = '\0';
  session->scrollback_len = 0;

  // Get list of all panes in the session
  snprintf(
      cmd, sizeof(cmd),
      "tmux list-panes -t %s -F "
      "'#{window_index}.#{pane_index}:#{pane_title}:#{pane_current_command}'",
      session->session_id);

  if (execute_tmux_command(cmd, pane_list, sizeof(pane_list)) != ERROR_NONE) {
    return ERROR_TMUX_CMD;
  }

  // If no panes found, try to get content anyway
  if (strlen(pane_list) == 0) {
    snprintf(cmd, sizeof(cmd), "tmux capture-pane -t %s -p",
             session->session_id);
    FILE *fp = popen(cmd, "r");
    if (fp) {
      session->scrollback_len =
          fread(session->scrollback, 1, sizeof(session->scrollback) - 1, fp);
      session->scrollback[session->scrollback_len] = '\0';
      pclose(fp);
    }
    return ERROR_NONE;
  }

  // Process each pane
  char *line = strtok(pane_list, "\n");
  int pane_count = 0;

  while (line != NULL &&
         session->scrollback_len < sizeof(session->scrollback) - 500) {
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
        int header_len =
            snprintf(session->scrollback + session->scrollback_len,
                     sizeof(session->scrollback) - session->scrollback_len,
                     "\n=== PANE %s (%s) ===\n", pane_id, pane_title);

        if (header_len > 0 && session->scrollback_len + header_len <
                                  sizeof(session->scrollback)) {
          session->scrollback_len += header_len;
        }

        // Add pane content (limit to avoid overflow)
        size_t available_space =
            sizeof(session->scrollback) - session->scrollback_len - 1;
        size_t copy_len =
            (content_len < available_space) ? content_len : available_space;

        if (copy_len > 0) {
          memcpy(session->scrollback + session->scrollback_len, temp_content,
                 copy_len);
          session->scrollback_len += copy_len;
          session->scrollback[session->scrollback_len] = '\0';
        }

        pane_count++;
      }
    }

    line = strtok(NULL, "\n");
  }

  // If we didn't capture any panes (all were empty/muxgeist), capture the
  // active pane
  if (pane_count == 0) {
    snprintf(cmd, sizeof(cmd), "tmux capture-pane -t %s -p",
             session->session_id);
    FILE *fp = popen(cmd, "r");
    if (fp) {
      session->scrollback_len =
          fread(session->scrollback, 1, sizeof(session->scrollback) - 1, fp);
      session->scrollback[session->scrollback_len] = '\0';
      pclose(fp);
    }
  }

  return ERROR_NONE;
}

muxgeist_error_t update_session_context(session_context_t *session) {
  char cmd[256];
  char output[MAX_BUFFER_SIZE];
  muxgeist_error_t rc = ERROR_NONE;

  // Get current pane
  snprintf(cmd, sizeof(cmd), "tmux display-message -t %s -p '#{pane_id}'",
           session->session_id);
  rc = execute_tmux_command(cmd, output, sizeof(output));
  if (rc == ERROR_NONE) {
    strncpy(session->current_pane, output, sizeof(session->current_pane) - 1);
  }

  // Get current working directory from active pane
  snprintf(cmd, sizeof(cmd),
           "tmux display-message -t %s -p '#{pane_current_path}'",
           session->session_id);
  rc = execute_tmux_command(cmd, output, sizeof(output));
  if (rc == ERROR_NONE) {
    strncpy(session->current_cwd, output, sizeof(session->current_cwd) - 1);
  }

  // Capture content from all panes
  rc = capture_all_panes(session);

  session->last_activity = time(NULL);
  return rc;
}

muxgeist_error_t scan_tmux_sessions(void) {
  char output[MAX_BUFFER_SIZE];
  muxgeist_error_t rc = execute_tmux_command(
      "tmux list-sessions -F '#{session_name}'", output, sizeof(output));

  if (rc != ERROR_NONE) {
    return rc;
  }

  // Parse session list
  char *line = strtok(output, "\n");
  while (line != NULL) {
    session_context_t *session = find_session(line);
    if (!session) {
      session = create_session(line);
      if (session) {
        printf("Discovered new tmux session: %s\n", line);
      }
    }

    if (session) {
      update_session_context(session);
    }

    line = strtok(NULL, "\n");
  }

  return ERROR_NONE;
}

void handle_client_request(int client_socket) {
  char buffer[MAX_BUFFER_SIZE];
  ssize_t bytes_read = recv(client_socket, buffer, sizeof(buffer) - 1, 0);

  if (bytes_read <= 0) {
    close(client_socket);
    return;
  }

  buffer[bytes_read] = '\0';
  printf("Received request: %s\n", buffer);

  // Simple protocol: "status", "context:session_id", "list"
  char response[MAX_BUFFER_SIZE];

  if (strcmp(buffer, "status") == 0) {
    snprintf(response, sizeof(response), "OK: %d sessions tracked",
             g_state.session_count);
  } else if (strncmp(buffer, "context:", 8) == 0) {
    char *session_id = buffer + 8;
    session_context_t *session = find_session(session_id);
    if (session) {
      snprintf(response, sizeof(response),
               "Session: %s\nCWD: %s\nPane: %s\nLast Activity: %ld\nScrollback "
               "Length: %d\nScrollback:\n%s\n",
               session->session_id, session->current_cwd, session->current_pane,
               session->last_activity, session->scrollback_len,
               session->scrollback);
    } else {
      snprintf(response, sizeof(response), "ERROR: Session not found");
    }
  } else if (strcmp(buffer, "list") == 0) {
    response[0] = '\0';
    for (int i = 0; i < g_state.session_count; i++) {
      char session_info[256];
      snprintf(session_info, sizeof(session_info), "%s (%s)\n",
               g_state.sessions[i].session_id, g_state.sessions[i].current_cwd);
      strncat(response, session_info, sizeof(response) - strlen(response) - 1);
    }
  } else {
    snprintf(response, sizeof(response), "ERROR: Unknown command");
  }

  send(client_socket, response, strlen(response), 0);
  close(client_socket);
}

int main(int argc, char *argv[]) {
  muxgeist_error_t rc = ERROR_NONE;

  printf("Starting Muxgeist daemon...\n");

  // Setup signal handling
  signal(SIGINT, signal_handler);
  signal(SIGTERM, signal_handler);

  // Initialize state
  g_state.running = 1;

  // Setup socket
  rc = setup_socket();
  if (rc != ERROR_NONE) {
    fprintf(stderr, "Failed to setup socket: %d\n", rc);
    return 1;
  }

  // Main loop
  fd_set readfds;
  struct timeval timeout;

  while (g_state.running) {
    // Scan for tmux sessions every iteration
    scan_tmux_sessions();

    // Setup select for socket
    FD_ZERO(&readfds);
    FD_SET(g_state.server_socket, &readfds);

    timeout.tv_sec = 2; // 2 second timeout
    timeout.tv_usec = 0;

    int activity =
        select(g_state.server_socket + 1, &readfds, NULL, NULL, &timeout);

    if (activity > 0 && FD_ISSET(g_state.server_socket, &readfds)) {
      int client_socket = accept(g_state.server_socket, NULL, NULL);
      if (client_socket >= 0) {
        handle_client_request(client_socket);
      }
    }
  }

  // Cleanup
  close(g_state.server_socket);
  unlink(MUXGEIST_SOCKET_PATH);
  printf("Muxgeist daemon stopped.\n");

  return 0;
}
