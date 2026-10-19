/*
 * Copyright (C) 2026 kaidev
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
 */

/*
 * Apple task port handling.
 *
 * Every Mach VM operation against another process starts with a task port.
 * Obtaining one is the single privilege-sensitive step of the whole tool, so
 * it is isolated here and reported with a precise errno.
 *
 * On a jailbroken device a root process holding the `task_for_pid-allow`
 * entitlement gets the port for any pid. Without it task_for_pid() fails with
 * KERN_FAILURE, which is surfaced to the user as EPERM plus a hint.
 */

#include "platform/plat_mach.h"

#if defined(__APPLE__)

#include <errno.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>

#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach/mach_traps.h>

/*
 * Not every public SDK revision declares task_for_pid() in its headers.
 * This prototype is identical to the system one, so the redeclaration is
 * harmless where the header already exports it.
 */
extern kern_return_t task_for_pid(mach_port_t target_tport, int pid,
                                  mach_port_t *t);

static pthread_mutex_t g_task_lock  = PTHREAD_MUTEX_INITIALIZER;
static mach_port_t     g_task       = MACH_PORT_NULL;
static pid_t           g_task_pid   = 0;
static int             g_task_owned = 0;   /* 1 when we must deallocate it */

int plat_mach_errno(kern_return_t kr)
{
    switch (kr) {
    case KERN_SUCCESS:            return 0;
    case KERN_INVALID_ARGUMENT:   return EINVAL;
    case KERN_PROTECTION_FAILURE: return EACCES;
    case KERN_INVALID_ADDRESS:    return EFAULT;
    case KERN_NO_SPACE:           return ENOMEM;
    case KERN_RESOURCE_SHORTAGE:  return ENOMEM;
    case KERN_FAILURE:            return EPERM;
    case KERN_INVALID_RIGHT:      return EPERM;
    case KERN_INVALID_NAME:       return EPERM;
    case KERN_INVALID_TASK:       return ESRCH;
    case MACH_SEND_INVALID_DEST:  return ESRCH;
    default:                      return EIO;
    }
}

mach_port_t plat_mach_task(pid_t pid)
{
    mach_port_t task = MACH_PORT_NULL;

    if (pid <= 0) {
        errno = EINVAL;
        return MACH_PORT_NULL;
    }

    pthread_mutex_lock(&g_task_lock);

    if (g_task != MACH_PORT_NULL && g_task_pid == pid) {
        task = g_task;
        pthread_mutex_unlock(&g_task_lock);
        return task;
    }

    if (g_task != MACH_PORT_NULL) {
        if (g_task_owned)
            mach_port_deallocate(mach_task_self(), g_task);
        g_task       = MACH_PORT_NULL;
        g_task_pid   = 0;
        g_task_owned = 0;
    }

    kern_return_t kr;
    if (pid == getpid()) {
        /* Our own task: no privilege check, and no right to give back. */
        task         = mach_task_self();
        g_task_owned = 0;
        kr           = KERN_SUCCESS;
    } else {
        kr = task_for_pid(mach_task_self(), (int)pid, &task);
        if (kr != KERN_SUCCESS) {
            errno = plat_mach_errno(kr);
            task  = MACH_PORT_NULL;
        } else {
            g_task_owned = 1;
        }
    }

    if (task != MACH_PORT_NULL) {
        g_task     = task;
        g_task_pid = pid;
    }

    pthread_mutex_unlock(&g_task_lock);
    return task;
}

void plat_mach_task_release(pid_t pid)
{
    pthread_mutex_lock(&g_task_lock);
    if (g_task != MACH_PORT_NULL && (pid <= 0 || g_task_pid == pid)) {
        if (g_task_owned)
            mach_port_deallocate(mach_task_self(), g_task);
        g_task       = MACH_PORT_NULL;
        g_task_pid   = 0;
        g_task_owned = 0;
    }
    pthread_mutex_unlock(&g_task_lock);
}

#endif /* __APPLE__ */
