CC ?= $(CROSS_COMPILE)gcc
CFLAGS ?= -Wall -Wextra -Werror -g
LDFLAGS ?=

TARGET = aesdsocket
SRCS = aesdsocket.c
OBJS = $(SRCS:.c=.o)

.PHONY: all clean default

all: $(TARGET)

default: all

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)
