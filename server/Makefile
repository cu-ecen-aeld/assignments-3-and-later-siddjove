TARGET = aesdsocket
SRC = aesdsocket.c

CC ?= $(CROSS_COMPILE)gcc
CFLAGS ?= -Wall -Wextra -O2

.PHONY: all clean

all:
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)

