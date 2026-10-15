/***************************************************************
 *
 * project   ____   _____  ____   ____   ____     _     _   _
 *       ___|  _ \ |_   _|| _  \ / ___| / ___|   / \   | \ | |
 *      / __| |_) |  | |  | |_) |\___ \|| |     / _ \  |  \| |
 *     | (__|  __/   | |  |  _ <  ___) || |__  / ___ \ | |\  |
 *      \___|_|      |_|  |_| \_|\____/ \____//_/   \_\|_| \_|
 *
 * Copyright (C) 2026 kaidev, <kaidevonmail@gmail.com>
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 ***************************************************************/

/*
 * Portable counting barrier.
 *
 * Darwin does not implement POSIX barriers (pthread_barrier_t is absent from
 * the macOS/iOS SDK), so on Apple platforms this header provides a
 * mutex/condvar based replacement with the same semantics. Everywhere else it
 * forwards to the real thing, unless PTRSCAN_FORCE_PORTABLE_BARRIER asks for
 * the portable one anyway -- which is how tests/test_barrier.c exercises it on
 * Linux.
 */

#ifndef PTRSCAN_PLAT_BARRIER_H
#define PTRSCAN_PLAT_BARRIER_H

#include <pthread.h>

#define PLAT_BARRIER_SERIAL_THREAD 1

#if defined(PTRSCAN_FORCE_PORTABLE_BARRIER) || defined(__APPLE__)

typedef struct plat_barrier {
    pthread_mutex_t mtx;
    pthread_cond_t  cv;
    unsigned        count;       /* number of participants */
    unsigned        waiting;     /* participants inside the current round */
    unsigned        generation;  /* round counter, bumped on release */
} plat_barrier_t;

static inline int plat_barrier_init(plat_barrier_t *b, unsigned count)
{
    if (count == 0)
        return -1;

    if (pthread_mutex_init(&b->mtx, NULL) != 0)
        return -1;
    if (pthread_cond_init(&b->cv, NULL) != 0) {
        pthread_mutex_destroy(&b->mtx);
        return -1;
    }
    b->count      = count;
    b->waiting    = 0;
    b->generation = 0;
    return 0;
}

static inline int plat_barrier_wait(plat_barrier_t *b)
{
    int serial = 0;

    pthread_mutex_lock(&b->mtx);

    unsigned gen = b->generation;
    if (++b->waiting == b->count) {
        /* Last arrival releases the round. */
        b->waiting = 0;
        b->generation++;
        serial = PLAT_BARRIER_SERIAL_THREAD;
        pthread_cond_broadcast(&b->cv);
    } else {
        while (gen == b->generation)
            pthread_cond_wait(&b->cv, &b->mtx);
    }

    pthread_mutex_unlock(&b->mtx);
    return serial;
}

static inline int plat_barrier_destroy(plat_barrier_t *b)
{
    pthread_cond_destroy(&b->cv);
    pthread_mutex_destroy(&b->mtx);
    return 0;
}

#else /* POSIX barriers available */

typedef pthread_barrier_t plat_barrier_t;

static inline int plat_barrier_init(plat_barrier_t *b, unsigned count)
{
    return pthread_barrier_init(b, NULL, count);
}

static inline int plat_barrier_wait(plat_barrier_t *b)
{
    return pthread_barrier_wait(b);
}

static inline int plat_barrier_destroy(plat_barrier_t *b)
{
    return pthread_barrier_destroy(b);
}

#endif /* portable vs POSIX */

#endif /* PTRSCAN_PLAT_BARRIER_H */
