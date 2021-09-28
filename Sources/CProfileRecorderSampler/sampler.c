//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#include <stdatomic.h>
#include <signal.h>
#include <stdio.h>
#include <pthread.h>
#include <stdbool.h>
#include <sys/time.h>
#include <string.h>

#include "os_dep.h"
#include "interface.h"
#include "asserts.h"


//#define UNSAFE_DEBUG(...) fprintf(stderr, "ProfileRecorder: " __VA_ARGS__)
#define UNSAFE_DEBUG(...)

struct collector_to_mutators g_swipr_c2ms = {0};

static inline void
swipr_state_start_preparing(void) {
    enum swipr_c2ms_state expected = swipr_c2m_idle;
    bool success = atomic_compare_exchange_strong_explicit(&g_swipr_c2ms.c2ms_state,
                                                           &expected,
                                                           swipr_c2m_preparing,
                                                           memory_order_relaxed,
                                                           memory_order_relaxed);
    swipr_precondition(success);
}

static inline void
swipr_state_start_sampling(void) {
    enum swipr_c2ms_state expected = swipr_c2m_preparing;
    bool success = atomic_compare_exchange_strong_explicit(&g_swipr_c2ms.c2ms_state,
                                                           &expected,
                                                           swipr_c2m_sampling,
                                                           memory_order_release,
                                                           memory_order_release);
    swipr_precondition(success);
}

static inline void
swipr_state_start_processing(void) {
    enum swipr_c2ms_state expected = swipr_c2m_sampling;
    bool success = atomic_compare_exchange_strong_explicit(&g_swipr_c2ms.c2ms_state,
                                                           &expected,
                                                           swipr_c2m_processing,
                                                           memory_order_acquire,
                                                           memory_order_acquire);
    swipr_precondition(success);
}

static inline void
swipr_state_finish_processing(void) {
    enum swipr_c2ms_state expected = swipr_c2m_processing;
    bool success = atomic_compare_exchange_strong_explicit(&g_swipr_c2ms.c2ms_state,
                                                           &expected,
                                                           swipr_c2m_idle,
                                                           memory_order_relaxed,
                                                           memory_order_relaxed);
    swipr_precondition(success);
}

struct swipr_stackframe {
    uintptr_t sf_ip;
    uintptr_t sf_sp;
};

struct swipr_minidump {
    pid_t md_pid;
    swipr_os_dep_thread_id md_tid;

    struct timespec md_time;

    size_t md_stack_depth;
    char md_thread_name[32];
    struct swipr_stackframe md_stack[SWIPR_MAX_STACK_DEPTH];
};

static void
swipr_dump_shared_objs(FILE *output) {
    struct swipr_dynamic_lib *all_libs = calloc(1024, sizeof(*all_libs));
    size_t all_libs_count = 0;
    swipr_os_dep_list_all_dynamic_libs(all_libs, 1024, &all_libs_count);

    fprintf(output, "[SWIPR] VERS { \"version\": 1}\n");
    for (size_t i=0; i < all_libs_count; i++) {
        fprintf(output,
                "[SWIPR] VMAP {"
                "\"path\": \"%s\", "
                "\"fileMappedAddress\": \"0x%lx\", "
                "\"segmentStartAddress\": \"0x%lx\", "
                "\"segmentEndAddress\": \"0x%lx\""
                "}\n",
                all_libs[i].dl_name, all_libs[i].dl_file_mapped_at,
                all_libs[i].dl_seg_start_addr, all_libs[i].dl_seg_end_addr);
    }
    free(all_libs);
}

static void
swipr_initialise_c2ms(FILE *output) {
    for (int i=0; i<SWIPR_MAX_MUTATOR_THREADS; i++) {
        g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id = 0;
        g_swipr_c2ms.c2ms_c2ms[i].c2m_proceed = NULL;
        g_swipr_c2ms.c2ms_c2ms[i].m2c_proceed = NULL;
    }

    swipr_dump_shared_objs(output);
}

static struct timespec
swipr_get_current_time(void) {
    struct timeval tv;
    struct timespec ts;
    gettimeofday(&tv, NULL);
    ts.tv_sec = tv.tv_sec + 0;
    ts.tv_nsec = ((typeof(ts.tv_nsec))tv.tv_usec) * 1000;

    return ts;
}

static void
swipr_make_sample(struct swipr_minidump *minidumps,
                 size_t minidumps_capacity,
                 size_t *minidumps_count_ptr) {
    swipr_state_start_preparing();

    struct thread_info all_threads[SWIPR_MAX_MUTATOR_THREADS];
    size_t num_threads = 0;
    int err = swipr_os_dep_list_all_threads(all_threads,
                                            SWIPR_MAX_MUTATOR_THREADS,
                                            &num_threads);
    swipr_precondition(err == 0);

    *minidumps_count_ptr = num_threads;

    UNSAFE_DEBUG("sampling %lu threads (controller is %lu)\n", num_threads, (uintptr_t)swipr_os_dep_get_thread_id());
    for (int i=0; i<num_threads; i++) {
        swipr_precondition(all_threads[i].ti_id != 0);
        g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id = all_threads[i].ti_id;
        g_swipr_c2ms.c2ms_c2ms[i].c2m_proceed = swipr_os_dep_sem_create(0);
        g_swipr_c2ms.c2ms_c2ms[i].m2c_proceed = swipr_os_dep_sem_create(0);
    }

    for (int i=0; i<num_threads; i++) {
        minidumps[i] = (typeof(minidumps[i])){ 0 };
    }

    swipr_state_start_sampling();

    struct timespec start_time = swipr_get_current_time();

    for (int i=0; i<num_threads; i++) {
        swipr_precondition(all_threads[i].ti_id != 0);
        UNSAFE_DEBUG("signalling thread %lu\n", (uintptr_t)g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id);
        err = swipr_os_dep_kill(all_threads[i].ti_id, SIGPROF);
        if (err != 0) {
            UNSAFE_DEBUG("couldn't signal thread %lu\n", (uintptr_t)g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id);
            // thread dead, let's not wait for it later.
            g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id = -1;
        }
    }

    swipr_os_dep_deadline deadline = swipr_os_dep_create_deadline();

    for (int i=0; i<num_threads; i++) {
        swipr_precondition(g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id != 0);
        if (g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id > 0) {
            swipr_os_dep_sem_wait(g_swipr_c2ms.c2ms_c2ms[i].m2c_proceed);
        }
    }

    swipr_state_start_processing();

    for (int i=0; i<num_threads; i++) {
        if (g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id == 0) {
            continue;
        }

        swipr_unw_cursor_t cursor = { 0 };
        swipr_unw_init_local(&cursor, &g_swipr_c2ms.c2ms_c2ms[i].c2m_context);

        int ret = -1;
        size_t next_stack_frame_idx = 0;
        while ((ret = swipr_unw_step(&cursor)) > 0 && next_stack_frame_idx < SWIPR_MAX_STACK_DEPTH) {
            struct swipr_stackframe *stack_frame = &minidumps[i].md_stack[next_stack_frame_idx++];
            swipr_unw_get_reg(&cursor, UNW_REG_IP, &stack_frame->sf_ip);
            swipr_unw_get_reg(&cursor, UNW_REG_SP, &stack_frame->sf_sp);

            UNSAFE_DEBUG("[%d: %lu] ip=%lx, sp=%lx, ret=%d\n",
                         i,
                         (uintptr_t)g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id,
                         stack_frame->sf_ip,
                         stack_frame->sf_sp,
                         ret);
        }
        minidumps[i].md_stack_depth = next_stack_frame_idx;
        minidumps[i].md_time = start_time;
        minidumps[i].md_pid = getpid();
        minidumps[i].md_tid = g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id;
        strcpy(minidumps[i].md_thread_name, all_threads[i].ti_name);
    }

    swipr_state_finish_processing();

    for (int i=0; i<num_threads; i++) {
        if (g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id > 0) {
            swipr_os_dep_sem_signal(g_swipr_c2ms.c2ms_c2ms[i].c2m_proceed);
        }
    }

    for (int i=0; i<num_threads; i++) {
        if (g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id > 0) {
            swipr_os_dep_sem_wait(g_swipr_c2ms.c2ms_c2ms[i].m2c_proceed);
        }

        g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id = 0;
        swipr_os_dep_sem_free(g_swipr_c2ms.c2ms_c2ms[i].c2m_proceed);
        swipr_os_dep_sem_free(g_swipr_c2ms.c2ms_c2ms[i].m2c_proceed);
        g_swipr_c2ms.c2ms_c2ms[i].c2m_proceed = NULL;
        g_swipr_c2ms.c2ms_c2ms[i].m2c_proceed = NULL;
    }
}

int
swipr_request_sample(FILE *output,
                     size_t sample_count,
                     useconds_t usecs_between_samples) {
    struct swipr_minidump *minidumps = calloc(SWIPR_MAX_MUTATOR_THREADS, sizeof(*minidumps));
    size_t num_minidumps = 0;

#if !defined(__linux__)
    fprintf(output,
            "[SWIPR] MESG { \"message\": \"Unsupported OS, cannot generate samples yet.\", \"exit\": 1 }\n");
    return 1;
#endif

    swipr_initialise_c2ms(output);

    for (size_t sample_no=0; sample_no<sample_count; sample_no++) {
        swipr_make_sample(minidumps, SWIPR_MAX_MUTATOR_THREADS, &num_minidumps);

        for (size_t t=0; t<num_minidumps; t++) {
            struct swipr_minidump *minidump = &minidumps[t];
            fprintf(output,
                    "[SWIPR] SMPL {"
                    "\"pid\": %d, "
                    "\"tid\": %lu, "
                    "\"name\": \"%s\", "
                    "\"timeSec\": %ld, "
                    "\"timeNSec\": %ld"
                    "}\n",
                    minidump->md_pid,
                    (uintptr_t)minidump->md_tid,
                    minidump->md_thread_name,
                    minidump->md_time.tv_sec,
                    minidump->md_time.tv_nsec
                    );

            for (size_t s=0; s<minidump->md_stack_depth; s++) {
                fprintf(output,
                        "[SWIPR] STCK {"
                        "\"ip\": \"0x%lx\", "
                        "\"sp\": \"0x%lx\""
                        "}\n",
                        minidump->md_stack[s].sf_ip,
                        minidump->md_stack[s].sf_sp
                        );
            }

            fprintf(output, "[SWIPR] DONE\n");
        }
        usleep(usecs_between_samples);
    }
    return 0;
}

static void
profiling_handler(int signo, siginfo_t *info, void *context)
{
    enum swipr_c2ms_state state = atomic_load_explicit(&g_swipr_c2ms.c2ms_state, memory_order_acquire);
    swipr_precondition(state == swipr_c2m_sampling);

    int my_idx = -1;
    const swipr_os_dep_thread_id my_thread_id = swipr_os_dep_get_thread_id();
    UNSAFE_DEBUG("thread %lu: collecting context\n", (uintptr_t)my_thread_id);
    for (int i=0; i<SWIPR_MAX_MUTATOR_THREADS; i++) {
        if (g_swipr_c2ms.c2ms_c2ms[i].c2m_thread_id == my_thread_id) {
            my_idx = i;
            break;
        }
    }
    swipr_precondition(my_idx >= 0);

    int err = swipr_unw_getcontext(&g_swipr_c2ms.c2ms_c2ms[my_idx].c2m_context);
    swipr_precondition(err == 0);
    UNSAFE_DEBUG("thread %lu: done collecting context\n", (uintptr_t)my_thread_id);
    swipr_os_dep_sem_signal(g_swipr_c2ms.c2ms_c2ms[my_idx].m2c_proceed);
    UNSAFE_DEBUG("thread %lu: waiting for collector\n", (uintptr_t)my_thread_id);
    swipr_os_dep_sem_wait(g_swipr_c2ms.c2ms_c2ms[my_idx].c2m_proceed);
    UNSAFE_DEBUG("thread %lu: continuing execution\n", (uintptr_t)my_thread_id);
    swipr_os_dep_sem_signal(g_swipr_c2ms.c2ms_c2ms[my_idx].m2c_proceed);
}

int swipr_initialize(void) {
    struct sigaction act = { 0 };

    act.sa_flags = SA_NODEFER;
    act.sa_sigaction = &profiling_handler;
    int err = sigaction(SIGPROF, &act, NULL);
    swipr_precondition(err == 0);

    return 0;
}
