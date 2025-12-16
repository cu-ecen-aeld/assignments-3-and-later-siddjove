CC ?= $(CROSS_COMPILE)gcc
CFLAGS ?= -Wall -Wextra -O2

TARGET = aesdsocket
SRC = aesdsocket.c

.PHONY: all clean

all:
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)

