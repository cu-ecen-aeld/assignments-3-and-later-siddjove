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

static volatile sig_atomic_t keep_running = 1;

static void signal_handler(int sig)
{
    (void)sig;
    keep_running = 0;
}

static void daemonize(void)
{
    pid_t pid = fork();
    if (pid > 0)
        exit(EXIT_SUCCESS);

    setsid();

    pid = fork();
    if (pid > 0)
        exit(EXIT_SUCCESS);

    chdir("/");
    umask(0);

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_WRONLY);
}

int main(int argc, char *argv[])
{
    bool daemon = false;
    if (argc == 2 && strcmp(argv[1], "-d") == 0)
        daemon = true;

    openlog("aesdsocket", LOG_PID, LOG_USER);

    struct sigaction sa = {0};
    sa.sa_handler = signal_handler;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0)
        exit(EXIT_FAILURE);

    int opt = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(sockfd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
        exit(EXIT_FAILURE);

    if (listen(sockfd, BACKLOG) < 0)
        exit(EXIT_FAILURE);

    if (daemon)
        daemonize();

    /* Ensure directory exists */
    mkdir("/var", 0755);
    mkdir("/var/tmp", 0755);

    while (keep_running) {
        int clientfd = accept(sockfd, NULL, NULL);
        if (clientfd < 0)
            continue;

        char buffer[1024];
        ssize_t bytes;

        int fd = open(DATA_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) {
            close(clientfd);
            continue;
        }

        /* === CRITICAL PART ===
         * Read UNTIL CLIENT CLOSES (recv == 0)
         * This handles autotest shutdown(SHUT_WR)
         */
        while ((bytes = recv(clientfd, buffer, sizeof(buffer), 0)) > 0) {
            write(fd, buffer, bytes);
        }

        close(fd);

        /* Send entire file back */
        fd = open(DATA_FILE, O_RDONLY);
        if (fd >= 0) {
            while ((bytes = read(fd, buffer, sizeof(buffer))) > 0) {
                send(clientfd, buffer, bytes, 0);
            }
            close(fd);
        }

        close(clientfd);
    }

    close(sockfd);
    remove(DATA_FILE);
    closelog();
    return 0;
}

