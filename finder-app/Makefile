CC=$(CROSS_COMPILE)gcc
CFLAGS=-Wall -Werror
TARGET=writer

all: $(TARGET)

$(TARGET): writer.c
	$(CC) $(CFLAGS) -o $(TARGET) writer.c

clean:
	rm -f $(TARGET) *.o
