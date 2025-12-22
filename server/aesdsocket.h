#ifndef AESDSOCKET_H
#define AESDSOCKET_H

#include <netinet/in.h>

#define MAX_PACKET_SIZE 65536
#define DATA_FILE "/var/tmp/aesdsocketdata"

struct clientInfo {
    int clientFD;
    struct sockaddr_in clientAddr;
};

int server_init(void);
void *processClientData(void *arg);

#endif

