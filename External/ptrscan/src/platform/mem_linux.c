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
 * Linux / Android process reader: process_vm_readv(2).
 *
 * This is already the contract the rest of the tool wants (short reads allowed,
 * -1 with errno on a hole), so the Mach backend in mem_apple.c is written to
 * match it rather than the other way round.
 */

#include "platform/plat_proc.h"

#if defined(__linux__)

#include <errno.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

ssize_t plat_proc_readv(pid_t pid,
                        const struct iovec *local_iov, unsigned long liovcnt,
                        const struct iovec *remote_iov, unsigned long riovcnt)
{
    return process_vm_readv(pid, local_iov, liovcnt, remote_iov, riovcnt, 0);
}

void plat_proc_release(pid_t pid)
{
    (void)pid;
}

const char *plat_proc_hint(void)
{
    return "reading another process needs root (or CAP_SYS_PTRACE) and a "
           "matching PTRACE_MODE_ATTACH_REALCREDS check; under a restrictive "
           "yama/ptrace_scope only descendants can be read";
}

void *plat_map_fixed(uint64_t addr, size_t len)
{
#ifndef MAP_FIXED_NOREPLACE
    /* Without MAP_FIXED_NOREPLACE the only fixed mapping is MAP_FIXED, which
     * silently replaces whatever is already there. Never do that. */
    (void)addr;
    (void)len;
    return NULL;
#else
    void *p;

    if (addr == 0 || len == 0)
        return NULL;

    p = mmap((void *)(uintptr_t)addr, len, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (p == MAP_FAILED || p != (void *)(uintptr_t)addr) {
        if (p != MAP_FAILED)
            munmap(p, len);
        return NULL;
    }
    return p;
#endif
}

#endif /* __linux__ */
