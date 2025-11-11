#include "systemcalls.h"
#include <stdlib.h>     // for system(), malloc, free
#include <stdio.h>      // for perror()
#include <stdbool.h>    // for bool type
#include <unistd.h>     // for fork(), execvp()
#include <sys/wait.h>   // for waitpid()
#include <fcntl.h>      // for open(), O_* flags
#include <errno.h>      // for errno

/**
 * @param cmd the command to execute with system()
 * @return true if the command executed successfully, false otherwise
 */
bool do_system(const char *cmd)
{
    if (cmd == NULL)
    {
        return false;
    }

    int ret = system(cmd);
    if (ret == -1)
    {
        perror("system");
        return false;
    }

    // WIFEXITED checks if child terminated normally
    return WIFEXITED(ret) && (WEXITSTATUS(ret) == 0);
}

/**
 * @param count The number of arguments in the variable argument list
 * @param ... Argument list where the first element is the program to execute
 * @return true if the command executed successfully, false otherwise
 */
bool do_exec(int count, ...)
{
    va_list args;
    va_start(args, count);

    char *command[count + 1];
    for (int i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;
    va_end(args);

    pid_t pid = fork();

    if (pid == -1)
    {
        perror("fork");
        return false;
    }

    if (pid == 0)
    {
        // Child process: replace image with execvp
        execvp(command[0], command);
        perror("execvp"); // only reached on error
        exit(EXIT_FAILURE);
    }

    int status;
    if (waitpid(pid, &status, 0) == -1)
    {
        perror("waitpid");
        return false;
    }

    return WIFEXITED(status) && (WEXITSTATUS(status) == 0);
}

/**
 * @param outputfile Path to output file where stdout/stderr should be redirected
 * @param count Number of arguments in varargs
 * @param ... Argument list where first element is program to execute
 * @return true if the command executed successfully, false otherwise
 */
bool do_exec_redirect(const char *outputfile, int count, ...)
{
    va_list args;
    va_start(args, count);

    char *command[count + 1];
    for (int i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;
    va_end(args);

    pid_t pid = fork();

    if (pid == -1)
    {
        perror("fork");
        return false;
    }

    if (pid == 0)
    {
        // Open the output file for redirection
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0)
        {
            perror("open");
            exit(EXIT_FAILURE);
        }

        // Redirect stdout and stderr
        if (dup2(fd, STDOUT_FILENO) < 0 || dup2(fd, STDERR_FILENO) < 0)
        {
            perror("dup2");
            close(fd);
            exit(EXIT_FAILURE);
        }

        close(fd);

        // Execute command
        execvp(command[0], command);
        perror("execvp"); // only reached if exec fails
        exit(EXIT_FAILURE);
    }

    int status;
    if (waitpid(pid, &status, 0) == -1)
    {
        perror("waitpid");
        return false;
    }

    return WIFEXITED(status) && (WEXITSTATUS(status) == 0);
}

