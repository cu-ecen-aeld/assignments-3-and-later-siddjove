#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <syslog.h>
#include <fcntl.h>

#define PORT 9000
#define BACKLOG 10
#define DATA_FILE "/var/tmp/aesdsocketdata"

static volatile sig_atomic_t running = 1;

static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

int main(int argc, char *argv[])
{
    (void)argc;
    (void)argv;   // IGNORE -d COMPLETELY

    openlog("aesdsocket", LOG_PID, LOG_USER);

    struct sigaction sa = {0};
    sa.sa_handler = signal_handler;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) exit(1);

    int opt = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(sockfd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
        exit(1);

    if (listen(sockfd, BACKLOG) < 0)
        exit(1);

    while (running) {
        int clientfd = accept(sockfd, NULL, NULL);
        if (clientfd < 0) continue;

        char buffer[1024];
        ssize_t n;

        int fd = open(DATA_FILE, O_CREAT | O_WRONLY | O_APPEND, 0644);

        while ((n = recv(clientfd, buffer, sizeof(buffer), 0)) > 0) {
            write(fd, buffer, n);
        }

        close(fd);

        fd = open(DATA_FILE, O_RDONLY);
        while ((n = read(fd, buffer, sizeof(buffer))) > 0) {
            send(clientfd, buffer, n, 0);
        }

        close(fd);
        close(clientfd);
    }

    close(sockfd);
    remove(DATA_FILE);
    closelog();
    return 0;
}

