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
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
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
    bool run_as_daemon = false;

    openlog("aesdsocket", LOG_PID, LOG_USER);

    if (argc == 2 && strcmp(argv[1], "-d") == 0) {
        run_as_daemon = true;
    } else if (argc > 1) {
        syslog(LOG_ERR, "Invalid arguments");
        return EXIT_FAILURE;
    }

    if (setup_signals() == -1) {
        syslog(LOG_ERR, "signal setup failed");
        return EXIT_FAILURE;
    }

    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) {
        syslog(LOG_ERR, "socket failed");
        return EXIT_FAILURE;
    }

    int opt = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in server_addr = {0};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(PORT);
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(sockfd, (struct sockaddr *)&server_addr, sizeof(server_addr)) == -1) {
        syslog(LOG_ERR, "bind failed");
        return EXIT_FAILURE;
    }

    if (listen(sockfd, BACKLOG) == -1) {
        syslog(LOG_ERR, "listen failed");
        return EXIT_FAILURE;
    }

    if (run_as_daemon && daemonize() == -1) {
        syslog(LOG_ERR, "daemonize failed");
        return EXIT_FAILURE;
    }

    while (!exit_requested) {
        struct sockaddr_in client_addr;
        socklen_t addrlen = sizeof(client_addr);
        int clientfd = accept(sockfd, (struct sockaddr *)&client_addr, &addrlen);
        if (clientfd == -1) {
            if (errno == EINTR) break;
            continue;
        }

        syslog(LOG_INFO, "Accepted connection");

        int data_fd = open(DATA_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (data_fd == -1) {
            close(clientfd);
            continue;
        }

        char buffer[1024];
        bool done = false;

        while (!done) {
            ssize_t bytes = recv(clientfd, buffer, sizeof(buffer), 0);
            if (bytes <= 0) {
                break;   // EOF OR error → process data
            }

            write(data_fd, buffer, bytes);

            if (memchr(buffer, '\n', bytes)) {
                done = true;
            }
        }

        close(data_fd);

        data_fd = open(DATA_FILE, O_RDONLY);
        if (data_fd != -1) {
            ssize_t rbytes;
            while ((rbytes = read(data_fd, buffer, sizeof(buffer))) > 0) {
                send(clientfd, buffer, rbytes, 0);
            }
            close(data_fd);
        }

        close(clientfd);
        syslog(LOG_INFO, "Closed connection");
    }

    close(sockfd);
    remove(DATA_FILE);
    closelog();
    return EXIT_SUCCESS;
}

