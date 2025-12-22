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
#include <sys/stat.h>

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

static void daemonize(void)
{
    if (fork() > 0) exit(EXIT_SUCCESS);
    setsid();
    if (fork() > 0) exit(EXIT_SUCCESS);

    chdir("/");
    umask(0);

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_WRONLY);
}

/* 🔴 REQUIRED for Buildroot */
static void ensure_var_tmp_exists(void)
{
    mkdir("/var", 0755);
    mkdir("/var/tmp", 0755);
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

    if (daemon)
        daemonize();

    while (!exit_requested) {
        int clientfd = accept(sockfd, NULL, NULL);
        if (clientfd < 0)
            continue;

        char buffer[1024];
        char *packet = NULL;
        size_t packet_len = 0;

        while (1) {
            ssize_t r = recv(clientfd, buffer, sizeof(buffer), 0);
            if (r <= 0)
                break;

            char *tmp = realloc(packet, packet_len + r);
            if (!tmp)
                break;

            packet = tmp;
            memcpy(packet + packet_len, buffer, r);
            packet_len += r;

            if (memchr(buffer, '\n', r))
                break;
        }

        if (packet_len > 0) {
            ensure_var_tmp_exists();

            int fd = open(DATA_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (fd >= 0) {
                write(fd, packet, packet_len);
                close(fd);
            }

            fd = open(DATA_FILE, O_RDONLY);
            if (fd >= 0) {
                while ((packet_len = read(fd, buffer, sizeof(buffer))) > 0)
                    send(clientfd, buffer, packet_len, 0);
                close(fd);
            }
        }

        free(packet);
        close(clientfd);
    }

    close(sockfd);
    remove(DATA_FILE);
    closelog();
    return 0;
}

