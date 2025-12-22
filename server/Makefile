CC ?= $(CROSS_COMPILE)gcc

TARGET = aesdsocket
OBJS = aesdsocket.o

CFLAGS = -Wall -Werror -pthread

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)

