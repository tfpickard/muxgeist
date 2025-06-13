CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -pedantic -g -O2
LDFLAGS = 

DAEMON_SRC = muxgeist-daemon.c
CLIENT_SRC = muxgeist-client.c
DAEMON_BIN = muxgeist-daemon
CLIENT_BIN = muxgeist-client

.PHONY: all clean test install

all: $(DAEMON_BIN) $(CLIENT_BIN)

$(DAEMON_BIN): $(DAEMON_SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(CLIENT_BIN): $(CLIENT_SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(DAEMON_BIN) $(CLIENT_BIN)
	rm -f /tmp/muxgeist.sock

test: $(DAEMON_BIN) $(CLIENT_BIN)
	@echo "=== Testing Muxgeist Daemon ==="
	@echo "1. Starting daemon in background..."
	@./$(DAEMON_BIN) &
	@DAEMON_PID=$$!; \
	sleep 2; \
	echo "2. Testing status command..."; \
	./$(CLIENT_BIN) status; \
	echo "3. Testing list command..."; \
	./$(CLIENT_BIN) list; \
	echo "4. Stopping daemon..."; \
	kill $$DAEMON_PID; \
	wait $$DAEMON_PID 2>/dev/null || true; \
	echo "=== Test Complete ==="

install: $(DAEMON_BIN) $(CLIENT_BIN)
	install -m 755 $(DAEMON_BIN) /usr/local/bin/
	install -m 755 $(CLIENT_BIN) /usr/local/bin/

debug: CFLAGS += -DDEBUG -g3
debug: $(DAEMON_BIN) $(CLIENT_BIN)

.SECONDARY:
