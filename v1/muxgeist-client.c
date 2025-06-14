#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define MUXGEIST_SOCKET_PATH "/tmp/muxgeist.sock"
#define MAX_BUFFER_SIZE 8192

typedef enum {
  ERROR_NONE = 0,
  ERROR_SOCKET_CREATE,
  ERROR_SOCKET_CONNECT,
  ERROR_SEND_FAILED,
  ERROR_RECV_FAILED,
  ERROR_UNKNOWN = 255
} client_error_t;

client_error_t send_command(const char *command, char *response,
                            size_t response_size) {
  int sock;
  struct sockaddr_un addr;

  sock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sock == -1) {
    perror("socket");
    return ERROR_SOCKET_CREATE;
  }

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, MUXGEIST_SOCKET_PATH, sizeof(addr.sun_path) - 1);

  if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
    perror("connect");
    close(sock);
    return ERROR_SOCKET_CONNECT;
  }

  if (send(sock, command, strlen(command), 0) == -1) {
    perror("send");
    close(sock);
    return ERROR_SEND_FAILED;
  }

  ssize_t bytes_received = recv(sock, response, response_size - 1, 0);
  if (bytes_received == -1) {
    perror("recv");
    close(sock);
    return ERROR_RECV_FAILED;
  }

  response[bytes_received] = '\0';
  close(sock);
  return ERROR_NONE;
}

void print_usage(const char *progname) {
  printf("Usage: %s <command>\n", progname);
  printf("Commands:\n");
  printf("  status              - Get daemon status\n");
  printf("  list                - List tracked sessions\n");
  printf("  context <session>   - Get context for specific session\n");
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    print_usage(argv[0]);
    return 1;
  }

  char command[256];
  char response[MAX_BUFFER_SIZE];
  client_error_t rc;

  if (strcmp(argv[1], "context") == 0 && argc == 3) {
    snprintf(command, sizeof(command), "context:%s", argv[2]);
  } else {
    strncpy(command, argv[1], sizeof(command) - 1);
    command[sizeof(command) - 1] = '\0';
  }

  rc = send_command(command, response, sizeof(response));

  if (rc != ERROR_NONE) {
    fprintf(stderr, "Failed to send command: %d\n", rc);
    return 1;
  }

  printf("%s\n", response);
  return 0;
}
