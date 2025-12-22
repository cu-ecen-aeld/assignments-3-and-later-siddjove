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

static int setup_signals(void)
{
    struct sigaction sa = {0};
    sa.sa_handler = signal_handler;

    if (sigaction(SIGINT, &sa, NULL) == -1) return -1;
    if (sigaction(SIGTERM, &sa, NULL) == -1) return -1;

    return 0;
}

static int daemonize(void)
{
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid > 0) exit(EXIT_SUCCESS);

    if (setsid() == -1) return -1;

    pid = fork();
    if (pid < 0) return -1;
    if (pid > 0) exit(EXIT_SUCCESS);

    chdir("/");
    umask(0);

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_WRONLY);

    return 0;
}

int main(int argc, char *argv[])
{
    int sockfd;
    bool daemon = false;

    openlog("aesdsocket", LOG_PID, LOG_USER);

    if (argc == 2 && strcmp(argv[1], "-d") == 0) {
        daemon = true;
    } else if (argc > 1) {
        syslog(LOG_ERR, "Invalid arguments");
        return EXIT_FAILURE;
    }

    if (setup_signals() == -1) {
        syslog(LOG_ERR, "Signal setup failed");
        return EXIT_FAILURE;
    }

    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) {
        syslog(LOG_ERR, "Socket failed");
        return EXIT_FAILURE;
    }

    int opt = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(sockfd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        syslog(LOG_ERR, "Bind failed");
        return EXIT_FAILURE;
    }

    if (listen(sockfd, BACKLOG) == -1) {
        syslog(LOG_ERR, "Listen failed");
        return EXIT_FAILURE;
    }

    if (daemon && daemonize() == -1) {
        syslog(LOG_ERR, "Daemonize failed");
        return EXIT_FAILURE;
    }

    while (!exit_requested) {
        struct sockaddr_in client;
        socklen_t len = sizeof(client);

        int clientfd = accept(sockfd, (struct sockaddr *)&client, &len);
        if (clientfd == -1) {
            if (errno == EINTR) break;
            continue;
        }

        syslog(LOG_INFO, "Accepted connection");

        char buffer[1024];
        char *packet = NULL;
        size_t packet_len = 0;
        bool done = false;

        while (!done) {
            ssize_t bytes = recv(clientfd, buffer, sizeof(buffer), 0);
            if (bytes <= 0) {
                break;  // EOF or error ends packet
            }

            char *tmp = realloc(packet, packet_len + bytes);
            if (!tmp) {
                free(packet);
                packet = NULL;
                break;
            }
            packet = tmp;

            memcpy(packet + packet_len, buffer, bytes);
            packet_len += bytes;

            if (memchr(buffer, '\n', bytes)) {
                done = true;
            }
        }

        if (packet && packet_len > 0) {
            int fd = open(DATA_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (fd != -1) {
                write(fd, packet, packet_len);
                close(fd);
            }

            fd = open(DATA_FILE, O_RDONLY);
            if (fd != -1) {
                ssize_t r;
                while ((r = read(fd, buffer, sizeof(buffer))) > 0) {
                    send(clientfd, buffer, r, 0);
                }
                close(fd);
            }
        }

        free(packet);
        close(clientfd);
        syslog(LOG_INFO, "Closed connection");
    }

    close(sockfd);
    remove(DATA_FILE);
    closelog();
    return EXIT_SUCCESS;
}

