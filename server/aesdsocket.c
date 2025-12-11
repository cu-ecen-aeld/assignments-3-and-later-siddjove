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
    sa.sa_flags = 0;

    if (sigaction(SIGINT, &sa, NULL) == -1) {
        return -1;
    }
    if (sigaction(SIGTERM, &sa, NULL) == -1) {
        return -1;
    }

    return 0;
}

static int daemonize(void)
{
    pid_t pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid > 0) {
        /* parent exits */
        exit(EXIT_SUCCESS);
    }

    /* child becomes session leader */
    if (setsid() == -1) {
        return -1;
    }

    pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    if (chdir("/") == -1) {
        return -1;
    }

    umask(0);

    /* close standard fds */
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    /* redirect to /dev/null */
    open("/dev/null", O_RDONLY); /* stdin */
    open("/dev/null", O_WRONLY); /* stdout */
    open("/dev/null", O_WRONLY); /* stderr */

    return 0;
}

int main(int argc, char *argv[])
{
    int sockfd = -1;
    int clientfd = -1;
    struct sockaddr_in server_addr;
    struct sockaddr_in client_addr;
    socklen_t client_addr_len;
    int optval = 1;
    bool run_as_daemon = false;

    openlog("aesdsocket", LOG_PID, LOG_USER);

    /* argument parsing */
    if (argc == 2 && strcmp(argv[1], "-d") == 0) {
        run_as_daemon = true;
    } else if (argc > 1) {
        fprintf(stderr, "Usage: %s [-d]\n", argv[0]);
        syslog(LOG_ERR, "Invalid arguments");
        closelog();
        return EXIT_FAILURE;
    }

    if (setup_signals() == -1) {
        syslog(LOG_ERR, "Failed to setup signal handlers: %s", strerror(errno));
        closelog();
        return EXIT_FAILURE;
    }

    /* create socket */
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) {
        syslog(LOG_ERR, "socket failed: %s", strerror(errno));
        closelog();
        return EXIT_FAILURE;
    }

    /* allow address reuse */
    if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)) == -1) {
        syslog(LOG_ERR, "setsockopt failed: %s", strerror(errno));
        close(sockfd);
        closelog();
        return EXIT_FAILURE;
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(PORT);
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(sockfd, (struct sockaddr *)&server_addr, sizeof(server_addr)) == -1) {
        syslog(LOG_ERR, "bind failed: %s", strerror(errno));
        close(sockfd);
        closelog();
        return EXIT_FAILURE;
    }

    if (listen(sockfd, BACKLOG) == -1) {
        syslog(LOG_ERR, "listen failed: %s", strerror(errno));
        close(sockfd);
        closelog();
        return EXIT_FAILURE;
    }
    syslog(LOG_INFO, "aesdsocket: listening on port %d", PORT);


    /* daemon mode (after successful bind/listen) */
    if (run_as_daemon) {
        if (daemonize() == -1) {
            syslog(LOG_ERR, "daemonize failed: %s", strerror(errno));
            close(sockfd);
            closelog();
            return EXIT_FAILURE;
        }
    }

    /* main accept loop */
    while (!exit_requested) {
        client_addr_len = sizeof(client_addr);
        clientfd = accept(sockfd, (struct sockaddr *)&client_addr, &client_addr_len);
        if (clientfd == -1) {
            if (errno == EINTR && exit_requested) {
                /* interrupted by signal while waiting on accept */
                break;
            }
            syslog(LOG_ERR, "accept failed: %s", strerror(errno));
            continue;
        }

        char client_ip[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &client_addr.sin_addr, client_ip, sizeof(client_ip)) == NULL) {
            strncpy(client_ip, "unknown", sizeof(client_ip));
            client_ip[sizeof(client_ip) - 1] = '\0';
        }

        syslog(LOG_INFO, "Accepted connection from %s", client_ip);

        /* receive data, write each received chunk immediately to the data file.
           Stop reading when a newline is seen in the chunk or when client closes. */
        char recv_buf[1024];
        bool saw_data = false;
        bool newline_found = false;

        while (!exit_requested) {
            ssize_t bytes = recv(clientfd, recv_buf, sizeof(recv_buf), 0);
            if (bytes < 0) {
                if (errno == EINTR && exit_requested) {
                    /* interrupted by signal while shutting down */
                    break;
                }
                syslog(LOG_ERR, "recv failed: %s", strerror(errno));
                break;
            } else if (bytes == 0) {
                /* client closed connection */
                break;
            }

            /* append this chunk to the data file */
            int data_fd = open(DATA_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (data_fd == -1) {
                syslog(LOG_ERR, "open data file failed: %s", strerror(errno));
                break;
            }
            ssize_t written = write(data_fd, recv_buf, (size_t)bytes);
            if (written == -1) {
                syslog(LOG_ERR, "write data file failed: %s", strerror(errno));
                close(data_fd);
                break;
            }
            close(data_fd);

            saw_data = true;

            /* check this chunk for newline */
            for (ssize_t i = 0; i < bytes; i++) {
                if (recv_buf[i] == '\n') {
                    newline_found = true;
                    break;
                }
            }

            if (newline_found) {
                /* stop reading further from this client after newline */
                break;
            }
        }

        /* if we received any data (newline or no-newline), send the entire file back */
        if (saw_data) {
            int read_fd = open(DATA_FILE, O_RDONLY);
            if (read_fd == -1) {
                syslog(LOG_ERR, "open data file for read failed: %s", strerror(errno));
            } else {
                ssize_t rbytes;
                while ((rbytes = read(read_fd, recv_buf, sizeof(recv_buf))) > 0) {
                    ssize_t sent = send(clientfd, recv_buf, (size_t)rbytes, 0);
                    if (sent == -1) {
                        syslog(LOG_ERR, "send failed: %s", strerror(errno));
                        break;
                    }
                }
                if (rbytes == -1) {
                    syslog(LOG_ERR, "read data file failed: %s", strerror(errno));
                }
                close(read_fd);
            }
        }

        close(clientfd);
        clientfd = -1;

        syslog(LOG_INFO, "Closed connection from %s", client_ip);
    }

    syslog(LOG_INFO, "Caught signal, exiting");

    if (sockfd != -1) {
        close(sockfd);
    }

    /* delete data file */
    if (remove(DATA_FILE) == -1 && errno != ENOENT) {
        syslog(LOG_ERR, "Failed to remove data file: %s", strerror(errno));
    }

    closelog();
    return EXIT_SUCCESS;
}

