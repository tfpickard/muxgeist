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
#define MAX_BUFFER_SIZE 8192
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

  if (fgets(output, output_size, fp) == NULL) {
    output[0] = '\0';
  }

  // Remove trailing newline
  size_t len = strlen(output);
  if (len > 0 && output[len - 1] == '\n') {
    output[len - 1] = '\0';
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

  // Get current working directory
  snprintf(cmd, sizeof(cmd),
           "tmux display-message -t %s -p '#{pane_current_path}'",
           session->session_id);
  rc = execute_tmux_command(cmd, output, sizeof(output));
  if (rc == ERROR_NONE) {
    strncpy(session->current_cwd, output, sizeof(session->current_cwd) - 1);
  }

  // Capture scrollback
  snprintf(cmd, sizeof(cmd), "tmux capture-pane -t %s -p", session->session_id);
  FILE *fp = popen(cmd, "r");
  if (fp) {
    session->scrollback_len =
        fread(session->scrollback, 1, sizeof(session->scrollback) - 1, fp);
    session->scrollback[session->scrollback_len] = '\0';
    pclose(fp);
  }

  session->last_activity = time(NULL);
  return ERROR_NONE;
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
               "Length: %d\n",
               session->session_id, session->current_cwd, session->current_pane,
               session->last_activity, session->scrollback_len);
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
