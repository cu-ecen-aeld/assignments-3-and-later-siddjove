#ifndef THREADING_H
#define THREADING_H

#include <stdbool.h>
#include <pthread.h>

/**
 * Data structure used to pass arguments to the thread
 * and to report success/failure back to the caller.
 */
struct thread_data {
    pthread_mutex_t *mutex;
    int wait_to_obtain_ms;
    int wait_to_release_ms;
    bool thread_complete_success;
};

/**
 * Thread function entry point.
 * See threading.c for implementation.
 */
void* threadfunc(void* thread_param);

/**
 * Starts a thread which:
 *  - waits wait_to_obtain_ms
 *  - locks the given mutex
 *  - waits wait_to_release_ms
 *  - unlocks the mutex
 * Returns true if the thread was successfully started.
 */
bool start_thread_obtaining_mutex(pthread_t *thread,
                                  pthread_mutex_t *mutex,
                                  int wait_to_obtain_ms,
                                  int wait_to_release_ms);

#endif // THREADING_H

