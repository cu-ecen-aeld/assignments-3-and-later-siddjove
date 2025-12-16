#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <syslog.h>
#include <fcntl.h>

#define PORT 9000
#define BACKLOG 10
#define DATA_FILE "/var/tmp/aesdsocketdata"

static volatile sig_atomic_t exit_requested = 0;

static void signal_handler(int signo)
{
    (void)signo;
    exit_requested = 1;
}

static void setup_signals(void)
{
    struct sigaction sa = {0};
    sa.sa_handler = signal_handler;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

int main(int argc, char *argv[])
{
    bool daemon = (argc == 2 && strcmp(argv[1], "-d") == 0);

    openlog("aesdsocket", LOG_PID, LOG_USER);
    setup_signals();

    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    bind(sockfd, (struct sockaddr *)&addr, sizeof(addr));
    listen(sockfd, BACKLOG);

    if (daemon && fork() > 0)
        exit(EXIT_SUCCESS);

    /* Clear file once per daemon start */
    unlink(DATA_FILE);

    while (!exit_requested) {
        int clientfd = accept(sockfd, NULL, NULL);
        if (clientfd < 0)
            continue;

        char buf[1024];
        char *packet = NULL;
        size_t packet_len = 0;

        while (1) {
            ssize_t r = recv(clientfd, buf, sizeof(buf), 0);
            if (r <= 0)
                break;

            char *tmp = realloc(packet, packet_len + r);
            if (!tmp) {
                free(packet);
                packet = NULL;
                packet_len = 0;
                break;
            }

            packet = tmp;
            memcpy(packet + packet_len, buf, r);
            packet_len += r;

            if (memchr(buf, '\n', r))
                break;
        }

        /* ✅ WRITE IF ANY DATA WAS RECEIVED */
        if (packet_len > 0) {
            int fd = open(DATA_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
            write(fd, packet, packet_len);
            close(fd);

            fd = open(DATA_FILE, O_RDONLY);
            while ((packet_len = read(fd, buf, sizeof(buf))) > 0)
                send(clientfd, buf, packet_len, 0);
            close(fd);
        }

        free(packet);
        close(clientfd);
    }

    close(sockfd);
    closelog();
    return 0;
}

