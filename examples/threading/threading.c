#include "threading.h"
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>   // just in case it's not already pulled in via threading.h

// Optional: use these functions to add debug or error prints to your application
#define DEBUG_LOG(msg,...)
//#define DEBUG_LOG(msg,...) printf("threading: " msg "\n" , ##__VA_ARGS__)
#define ERROR_LOG(msg,...) printf("threading ERROR: " msg "\n" , ##__VA_ARGS__)

/**
 * Thread entry function.
 * Behavior required by the assignment/tests:
 *  - Wait wait_to_obtain_ms
 *  - Lock the mutex
 *  - Wait wait_to_release_ms
 *  - Unlock the mutex
 *  - Set thread_complete_success = true on success
 *  - Return the same thread_data pointer that was passed in
 */
void* threadfunc(void* thread_param)
{
    if (thread_param == NULL) {
        ERROR_LOG("thread_param is NULL");
        return NULL;
    }

    struct thread_data* thread_func_args = (struct thread_data *) thread_param;

    // Wait before attempting to obtain the mutex
    if (thread_func_args->wait_to_obtain_ms > 0) {
        if (usleep(thread_func_args->wait_to_obtain_ms * 1000) != 0) {
            ERROR_LOG("usleep before obtain was interrupted");
        }
    }

    // Obtain the mutex
    int rc = pthread_mutex_lock(thread_func_args->mutex);
    if (rc != 0) {
        ERROR_LOG("pthread_mutex_lock failed (%d)", rc);
        thread_func_args->thread_complete_success = false;
        return thread_param;
    }

    // Wait while holding the mutex
    if (thread_func_args->wait_to_release_ms > 0) {
        if (usleep(thread_func_args->wait_to_release_ms * 1000) != 0) {
            ERROR_LOG("usleep before release was interrupted");
        }
    }

    // Release the mutex
    rc = pthread_mutex_unlock(thread_func_args->mutex);
    if (rc != 0) {
        ERROR_LOG("pthread_mutex_unlock failed (%d)", rc);
        thread_func_args->thread_complete_success = false;
        return thread_param;
    }

    // If we got here, everything worked
    thread_func_args->thread_complete_success = true;

    // The tests expect the thread to return a pointer to struct thread_data
    return thread_param;
}

/**
 * Create a thread which:
 *  - waits wait_to_obtain_ms,
 *  - obtains the given mutex,
 *  - waits wait_to_release_ms,
 *  - releases the mutex,
 *  - then exits.
 *
 * Returns true if the thread was successfully started, false otherwise.
 */
bool start_thread_obtaining_mutex(pthread_t *thread, pthread_mutex_t *mutex,
                                  int wait_to_obtain_ms, int wait_to_release_ms)
{
    if (thread == NULL || mutex == NULL) {
        ERROR_LOG("start_thread_obtaining_mutex called with NULL argument");
        return false;
    }

    struct thread_data *data = malloc(sizeof(struct thread_data));
    if (data == NULL) {
        ERROR_LOG("malloc for thread_data failed");
        return false;
    }

    // Fill in the thread data structure as defined in threading.h
    data->mutex = mutex;
    data->wait_to_obtain_ms = wait_to_obtain_ms;
    data->wait_to_release_ms = wait_to_release_ms;
    data->thread_complete_success = false;   // will be set true by threadfunc on success

    int rc = pthread_create(thread, NULL, threadfunc, data);
    if (rc != 0) {
        ERROR_LOG("pthread_create failed (%d)", rc);
        free(data);
        return false;
    }

    // On success, ownership of 'data' lifetime is now with the thread/test code
    // (the unit test frees the pointer returned by threadfunc).
    return true;
}

