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
 * iOS / macOS process reader: mach_vm_read_overwrite(2).
 *
 * process_vm_readv(2) is not the only thing that differs; it also reads
 * *partially*. mach_vm_read_overwrite() is all-or-nothing: one unreadable page
 * anywhere in an 8 MB chunk fails the whole call. The index builder relies on
 * partial reads to step over holes, so read_range() reconstructs them: when a
 * range fails it is halved until the readable prefix is found, and the first
 * failing page ends the walk. The cost of a hole is O(log n) Mach calls, and
 * the resulting contract is exactly process_vm_readv()'s.
 */

#include "platform/plat_proc.h"

#if defined(__APPLE__)

#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

#include <mach/mach.h>

#include "platform/plat_mach.h"

/*
 * Split granularity. iOS uses 16 KB pages on modern arm64 devices and 4 KB on
 * older ones; splitting at 4 KB is valid on both (a sub-page range simply maps
 * onto the enclosing page).
 */
#define PLAT_SPLIT_MIN 4096u

static ssize_t read_range(mach_port_t task, uint64_t remote,
                          void *local, size_t len)
{
    if (len == 0)
        return 0;

    mach_vm_size_t got = 0;
    kern_return_t kr = mach_vm_read_overwrite(task,
                                              (mach_vm_address_t)remote,
                                              (mach_vm_size_t)len,
                                              (mach_vm_address_t)(uintptr_t)local,
                                              &got);
    if (kr == KERN_SUCCESS)
        return (ssize_t)got;

    if (len <= PLAT_SPLIT_MIN) {
        errno = plat_mach_errno(kr);
        return -1;
    }

    size_t half = (len / 2) & ~(size_t)(PLAT_SPLIT_MIN - 1);
    if (half == 0)
        half = PLAT_SPLIT_MIN;

    ssize_t first = read_range(task, remote, local, half);
    if (first < 0)
        return -1;
    if ((size_t)first < half)
        return first;                   /* hole inside the first half */

    ssize_t second = read_range(task, remote + half,
                                (char *)local + half, len - half);
    if (second < 0)
        return first;

    return first + second;
}

ssize_t plat_proc_readv(pid_t pid,
                        const struct iovec *local_iov, unsigned long liovcnt,
                        const struct iovec *remote_iov, unsigned long riovcnt)
{
    if (!local_iov || !remote_iov || liovcnt == 0 || riovcnt == 0) {
        errno = EINVAL;
        return -1;
    }
    if (riovcnt > liovcnt) {
        errno = EINVAL;
        return -1;
    }

    mach_port_t task = plat_mach_task(pid);
    if (task == MACH_PORT_NULL)
        return -1;

    ssize_t total = 0;

    for (unsigned long i = 0; i < riovcnt; i++) {
        size_t want = remote_iov[i].iov_len;
        if (local_iov[i].iov_len < want)
            want = local_iov[i].iov_len;
        if (want == 0)
            continue;

        ssize_t n = read_range(task,
                               (uint64_t)(uintptr_t)remote_iov[i].iov_base,
                               local_iov[i].iov_base, want);
        if (n < 0)
            return total > 0 ? total : -1;

        total += n;
        if ((size_t)n < want)
            return total;               /* stop at the first hole */
    }

    return total;
}

void plat_proc_release(pid_t pid)
{
    plat_mach_task_release(pid);
}

const char *plat_proc_hint(void)
{
    return "task_for_pid() failed: on iOS the tool must run as root (jailbroken "
           "or TrollStore device) with the task_for_pid-allow entitlement "
           "codesigned into the binary";
}

#ifndef VM_FLAGS_FIXED
#define VM_FLAGS_FIXED 0x0000
#endif

void *plat_map_fixed(uint64_t addr, size_t len)
{
    mach_vm_address_t a = (mach_vm_address_t)addr;

    if (addr == 0 || len == 0)
        return NULL;

    /* VM_FLAGS_FIXED, never VM_FLAGS_OVERWRITE: an address that is in use has
     * to fail, not lose whatever was already mapped there. */
    if (mach_vm_allocate(mach_task_self(), &a, (mach_vm_size_t)len,
                         VM_FLAGS_FIXED) != KERN_SUCCESS)
        return NULL;

    return (void *)(uintptr_t)a;
}

#endif /* __APPLE__ */
