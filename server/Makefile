CC ?= gcc
CFLAGS ?= -Wall -Wextra -O2
LDFLAGS ?=

.PHONY: all
all: aesdsocket

aesdsocket: aesdsocket.c
	$(CC) $(CFLAGS) -o $@ aesdsocket.c $(LDFLAGS)

.PHONY: clean
clean:
	-rm -f aesdsocket

