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
#include <stdatomic.h>
#include <signal.h>
#include <stdio.h>
#include <pthread.h>
#include <stdbool.h>
#include <sys/time.h>

#include "os_dep.h"
#include "interface.h"
#include "asserts.h"


//#define UNSAFE_DEBUG(...) fprintf(stderr, "CSPL: " __VA_ARGS__)
#define UNSAFE_DEBUG(...)

struct collector_to_mutators g_cspl_c2ms = {0};

static inline void
cspl_state_start_preparing(void) {
    enum cspl_c2ms_state expected = cspl_c2m_idle;
    bool success = atomic_compare_exchange_strong_explicit(&g_cspl_c2ms.c2ms_state,
                                                           &expected,
                                                           cspl_c2m_preparing,
                                                           memory_order_relaxed,
                                                           memory_order_relaxed);
    cspl_precondition(success);
}

static inline void
cspl_state_start_sampling(void) {
    enum cspl_c2ms_state expected = cspl_c2m_preparing;
    bool success = atomic_compare_exchange_strong_explicit(&g_cspl_c2ms.c2ms_state,
                                                           &expected,
                                                           cspl_c2m_sampling,
                                                           memory_order_release,
                                                           memory_order_release);
    cspl_precondition(success);
}

static inline void
cspl_state_start_processing(void) {
    enum cspl_c2ms_state expected = cspl_c2m_sampling;
    bool success = atomic_compare_exchange_strong_explicit(&g_cspl_c2ms.c2ms_state,
                                                           &expected,
                                                           cspl_c2m_processing,
                                                           memory_order_acquire,
                                                           memory_order_acquire);
    cspl_precondition(success);
}

static inline void
cspl_state_finish_processing(void) {
    enum cspl_c2ms_state expected = cspl_c2m_processing;
    bool success = atomic_compare_exchange_strong_explicit(&g_cspl_c2ms.c2ms_state,
                                                           &expected,
                                                           cspl_c2m_idle,
                                                           memory_order_relaxed,
                                                           memory_order_relaxed);
    cspl_precondition(success);
}

pthread_t target = 0; // remove

struct cspl_stackframe {
    uintptr_t sf_ip;
    uintptr_t sf_sp;
};

struct cspl_minidump {
    pid_t md_pid;
    os_dep_thread_id md_tid;

    struct timespec md_time;

    size_t md_stack_depth;
    struct cspl_stackframe md_stack[CSPL_MAX_STACK_DEPTH];
};

__attribute__((constructor))

static void
cspl_dump_shared_objs(void) {
    struct cspl_dynamic_lib all_libs[1024] = {0};
    size_t all_libs_count = 0;
    os_dep_list_all_dynamic_libs(all_libs, sizeof(all_libs)/sizeof(all_libs[0]), &all_libs_count);

    for (size_t i=0; i < all_libs_count; i++) {
        fprintf(stderr,
                "[CSPL] VMAP {"
                "\"path\": \"%s\", "
                "\"fileMappedAddress\": \"0x%lx\", "
                "\"segmentStartAddress\": \"0x%lx\", "
                "\"segmentEndAddress\": \"0x%lx\""
                "}\n",
                all_libs[i].dl_name, all_libs[i].dl_file_mapped_at,
                all_libs[i].dl_seg_start_addr, all_libs[i].dl_seg_end_addr);
    }
}

static void
cspl_initialise_c2ms(void) {
    for (int i=0; i<CSPL_MAX_MUTATOR_THREADS; i++) {
        g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id = 0;
        g_cspl_c2ms.c2ms_c2ms[i].c2m_proceed = NULL;
        g_cspl_c2ms.c2ms_c2ms[i].m2c_proceed = NULL;
    }

    cspl_dump_shared_objs();
}

static struct timespec
cspl_get_current_time(void) {
    struct timeval tv;
    struct timespec ts;
    gettimeofday(&tv, NULL);
    ts.tv_sec = tv.tv_sec + 0;
    ts.tv_nsec = ((typeof(ts.tv_nsec))tv.tv_usec) * 1000;

    return ts;
}

static void
cspl_make_sample(struct cspl_minidump *minidumps,
                 size_t minidumps_capacity,
                 size_t *minidumps_count_ptr) {
    cspl_state_start_preparing();

    os_dep_thread_id all_threads[CSPL_MAX_MUTATOR_THREADS];
    size_t num_threads = 0;
    int err = os_dep_list_all_threads(all_threads,
                                      CSPL_MAX_MUTATOR_THREADS,
                                      &num_threads);
    cspl_precondition(err == 0);

    *minidumps_count_ptr = num_threads;

    UNSAFE_DEBUG("sampling %lu threads (controller is %lu)\n", num_threads, (uintptr_t)os_dep_get_thread_id());
    for (int i=0; i<num_threads; i++) {
        cspl_precondition(all_threads[i] != 0);
        g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id = all_threads[i];
        g_cspl_c2ms.c2ms_c2ms[i].c2m_proceed = os_dep_sem_create(0);
        g_cspl_c2ms.c2ms_c2ms[i].m2c_proceed = os_dep_sem_create(0);
    }

    for (int i=0; i<num_threads; i++) {
        minidumps[i] = (typeof(minidumps[i])){ 0 };
    }

    cspl_state_start_sampling();

    struct timespec start_time = cspl_get_current_time();

    for (int i=0; i<num_threads; i++) {
        cspl_precondition(all_threads[i] != 0);
        UNSAFE_DEBUG("signalling thread %lu\n", (uintptr_t)g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id);
        err = os_dep_kill(all_threads[i], SIGPROF);
        if (err != 0) {
            UNSAFE_DEBUG("couldn't signal thread %lu\n", (uintptr_t)g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id);
            // thread dead, let's not wait for it later.
            g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id = -1;
        }
    }

    os_dep_deadline deadline = os_dep_create_deadline();

    for (int i=0; i<num_threads; i++) {
        cspl_precondition(g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id != 0);
        if (g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id > 0) {
            os_dep_sem_wait(g_cspl_c2ms.c2ms_c2ms[i].m2c_proceed);
        }
    }

    cspl_state_start_processing();

    for (int i=0; i<num_threads; i++) {
        if (g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id == 0) {
            continue;
        }

        swift_unwind_unw_cursor_t cursor = { 0 };
        swift_unwind_unw_init_local(&cursor, &g_cspl_c2ms.c2ms_c2ms[i].c2m_context);

        int ret = -1;
        size_t next_stack_frame_idx = 0;
        while ((ret = swift_unwind_unw_step(&cursor)) > 0 && next_stack_frame_idx < CSPL_MAX_STACK_DEPTH) {
            struct cspl_stackframe *stack_frame = &minidumps[i].md_stack[next_stack_frame_idx++];
            swift_unwind_unw_get_reg(&cursor, UNW_REG_IP, &stack_frame->sf_ip);
            swift_unwind_unw_get_reg(&cursor, UNW_REG_SP, &stack_frame->sf_sp);

            UNSAFE_DEBUG("[%d: %lu] ip=%lx, sp=%lx, ret=%d\n",
                         i,
                         (uintptr_t)g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id,
                         stack_frame->sf_ip,
                         stack_frame->sf_sp,
                         ret);
        }
        minidumps[i].md_stack_depth = next_stack_frame_idx;
        minidumps[i].md_time = start_time;
        minidumps[i].md_pid = getpid();
        minidumps[i].md_tid = g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id;
    }

    cspl_state_finish_processing();

    for (int i=0; i<num_threads; i++) {
        if (g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id > 0) {
            os_dep_sem_signal(g_cspl_c2ms.c2ms_c2ms[i].c2m_proceed);
        }
    }

    for (int i=0; i<num_threads; i++) {
        if (g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id > 0) {
            os_dep_sem_wait(g_cspl_c2ms.c2ms_c2ms[i].m2c_proceed);
        }

        g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id = 0;
        os_dep_sem_free(g_cspl_c2ms.c2ms_c2ms[i].c2m_proceed);
        os_dep_sem_free(g_cspl_c2ms.c2ms_c2ms[i].m2c_proceed);
        g_cspl_c2ms.c2ms_c2ms[i].c2m_proceed = NULL;
        g_cspl_c2ms.c2ms_c2ms[i].m2c_proceed = NULL;
    }
}

int
cspl_request_sample(void) {
    struct cspl_minidump *minidumps = calloc(CSPL_MAX_MUTATOR_THREADS, sizeof(*minidumps));
    size_t num_minidumps = 0;

    while (1) {
    cspl_make_sample(minidumps, CSPL_MAX_MUTATOR_THREADS, &num_minidumps);

    for (size_t t=0; t<num_minidumps; t++) {
        struct cspl_minidump *minidump = &minidumps[t];
        fprintf(stderr,
                "[CSPL] SMPL {"
                "\"pid\": %d, "
                "\"tid\": %lu, "
                "\"timeSec\": %ld, "
                "\"timeNSec\": %ld"
                "}\n",
                minidump->md_pid,
                (uintptr_t)minidump->md_tid,
                minidump->md_time.tv_sec,
                minidump->md_time.tv_nsec
                );

        for (size_t s=0; s<minidump->md_stack_depth; s++) {
            fprintf(stderr,
                    "[CSPL] STCK {"
                    "\"ip\": \"0x%lx\", "
                    "\"sp\": \"0x%lx\""
                    "}\n",
                    minidump->md_stack[s].sf_ip,
                    minidump->md_stack[s].sf_sp
                    );
        }

        fprintf(stderr, "[CSPL] DONE\n");
    }
        usleep(100000);
    }
}

static void
profiling_handler(int signo, siginfo_t *info, void *context)
{
    enum cspl_c2ms_state state = atomic_load_explicit(&g_cspl_c2ms.c2ms_state, memory_order_acquire);
    cspl_precondition(state == cspl_c2m_sampling);

    int my_idx = -1;
    const os_dep_thread_id my_thread_id = os_dep_get_thread_id();
    UNSAFE_DEBUG("thread %lu: collecting context\n", (uintptr_t)my_thread_id);
    for (int i=0; i<CSPL_MAX_MUTATOR_THREADS; i++) {
        if (g_cspl_c2ms.c2ms_c2ms[i].c2m_thread_id == my_thread_id) {
            my_idx = i;
            break;
        }
    }
    cspl_precondition(my_idx >= 0);

    int err = swift_unwind_unw_getcontext(&g_cspl_c2ms.c2ms_c2ms[my_idx].c2m_context);
    cspl_precondition(err == 0);
    UNSAFE_DEBUG("thread %lu: done collecting context\n", (uintptr_t)my_thread_id);
    os_dep_sem_signal(g_cspl_c2ms.c2ms_c2ms[my_idx].m2c_proceed);
    UNSAFE_DEBUG("thread %lu: waiting for collector\n", (uintptr_t)my_thread_id);
    os_dep_sem_wait(g_cspl_c2ms.c2ms_c2ms[my_idx].c2m_proceed);
    UNSAFE_DEBUG("thread %lu: continuing execution\n", (uintptr_t)my_thread_id);
    os_dep_sem_signal(g_cspl_c2ms.c2ms_c2ms[my_idx].m2c_proceed);
}

int cspl_initialize(void) {
    struct sigaction act = { 0 };

    act.sa_flags = SA_NODEFER;
    act.sa_sigaction = &profiling_handler;
    int err = sigaction(SIGPROF, &act, NULL);
    cspl_precondition(err == 0);
}
