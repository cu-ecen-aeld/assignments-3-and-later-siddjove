#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <syslog.h>

#include "aesdsocket.h"

static volatile sig_atomic_t keepRunning = 1;

static void sig_handler(int signo)
{
    (void)signo;
    keepRunning = 0;
}

int server_init(void)
{
    int sockfd;
    struct sockaddr_in addr = {0};

    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0)
        return -1;

    int enable = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &enable, sizeof(int));

    addr.sin_family = AF_INET;
    addr.sin_port = htons(9000);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(sockfd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
        return -1;

    return sockfd;
}

void *processClientData(void *arg)
{
    struct clientInfo *client = (struct clientInfo *)arg;
    char buffer[MAX_PACKET_SIZE];

    int fd = open(DATA_FILE, O_CREAT | O_RDWR | O_APPEND, 0644);
    if (fd < 0)
        goto cleanup;

    ssize_t bytes;
    while ((bytes = recv(client->clientFD, buffer, sizeof(buffer), 0)) > 0) {

        /* write received data */
        write(fd, buffer, bytes);

        /* rewind and send full file back */
        lseek(fd, 0, SEEK_SET);
        ssize_t r;
        while ((r = read(fd, buffer, sizeof(buffer))) > 0) {
            send(client->clientFD, buffer, r, 0);
        }
        lseek(fd, 0, SEEK_END);
    }

cleanup:
    close(fd);
    close(client->clientFD);
    free(client);
    return NULL;
}

int main(int argc, char *argv[])
{
    int daemonize = 0;
    int opt;

    while ((opt = getopt(argc, argv, "d")) != -1) {
        if (opt == 'd')
            daemonize = 1;
    }

    openlog("aesdsocket", LOG_PID, LOG_USER);

    struct sigaction sa = {0};
    sa.sa_handler = sig_handler;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    int sockfd = server_init();
    if (sockfd < 0)
        return -1;

    if (daemonize) {
        if (fork() > 0)
            exit(0);
        setsid();
        chdir("/");
        close(STDIN_FILENO);
        close(STDOUT_FILENO);
        close(STDERR_FILENO);
        open("/dev/null", O_RDWR);
        dup(0);
        dup(0);
    }

    listen(sockfd, 5);
    remove(DATA_FILE);

    while (keepRunning) {
        struct clientInfo *client = malloc(sizeof(*client));
        socklen_t len = sizeof(client->clientAddr);

        client->clientFD =
            accept(sockfd, (struct sockaddr *)&client->clientAddr, &len);

        if (client->clientFD < 0) {
            free(client);
            continue;
        }

        syslog(LOG_INFO, "Accepted connection from %s",
               inet_ntoa(client->clientAddr.sin_addr));

        pthread_t tid;
        pthread_create(&tid, NULL, processClientData, client);
        pthread_detach(tid);
    }

    close(sockfd);
    remove(DATA_FILE);
    closelog();
    return 0;
}

