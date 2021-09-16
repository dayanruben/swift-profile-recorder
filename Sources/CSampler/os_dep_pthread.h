//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2022-2025 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//
//  Header.h
//  Header
//
//  Created by Johannes Weiss on 15/09/2021.
//

#ifndef os_dep_pthread_h
#define os_dep_pthread_h

#include <pthread.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/errno.h>

#include "asserts.h"
#include "os_dep_linux.h"

struct cspl_pthread_sem {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int value;
};

typedef struct cspl_pthread_sem *os_dep_sem;
static inline os_dep_sem
os_dep_sem_create(int value) {
    struct cspl_pthread_sem *sem = malloc(sizeof(*sem));
    cspl_precondition(sem != NULL);

    *sem = (typeof(*sem)){ 0 };
    sem->value = 0;

    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ERRORCHECK);
    pthread_mutex_init(&sem->mutex, &attr);

    pthread_cond_init(&sem->cond, NULL);

    return sem;
}

static inline void
os_dep_sem_free(os_dep_sem sem) {
    int err = pthread_cond_destroy(&sem->cond);
    cspl_precondition(err == 0);

    err = pthread_mutex_destroy(&sem->mutex);
    cspl_precondition(err == 0);

    free(sem);
}

static inline void
os_dep_sem_signal(os_dep_sem sem) {
    int err = pthread_mutex_lock(&sem->mutex);
    cspl_precondition(err == 0);

    cspl_precondition(sem->value >= 0);
    sem->value++;

    err = pthread_mutex_unlock(&sem->mutex);
    cspl_precondition(err == 0);

    err = pthread_cond_signal(&sem->cond);
    cspl_precondition(err == 0);
}

#define os_dep_deadline struct timespec

static inline os_dep_deadline
os_dep_create_deadline(void) {
    struct timeval tv;
    struct timespec ts;
    gettimeofday(&tv, NULL);
    ts.tv_sec = tv.tv_sec + 0;
    ts.tv_nsec = 0;

    return ts;
}

static inline void
os_dep_sem_wait(os_dep_sem sem) {
    int err = pthread_mutex_lock(&sem->mutex);
    cspl_precondition(err == 0);

    cspl_precondition(sem->value >= 0);
    while (sem->value <= 0) {
        err = pthread_cond_wait(&sem->cond, &sem->mutex);
        cspl_precondition(err == 0);
    }
    sem->value--;
    cspl_precondition(sem->value >= 0);

    err = pthread_mutex_unlock(&sem->mutex);
    cspl_precondition(err == 0);
}

static inline int
os_dep_sem_wait_with_deadline(os_dep_sem sem, os_dep_deadline deadline) {
    int err = pthread_mutex_lock(&sem->mutex);
    cspl_precondition(err == 0);

    while (sem->value <= 0) {
        err = pthread_cond_timedwait(&sem->cond, &sem->mutex, &deadline);
        if (err == ETIMEDOUT) {
            err = pthread_mutex_unlock(&sem->mutex);
            cspl_precondition(err == 0);

            return ETIMEDOUT;
        }
        cspl_precondition(err == 0);
    }
    sem->value--;
    cspl_precondition(sem->value >= 0);

    err = pthread_mutex_unlock(&sem->mutex);
    cspl_precondition(err == 0);

    return 0;
}

#endif /* os_dep_pthread_h */
