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
 * iOS / macOS memory map backend: Mach VM regions.
 *
 * There is no /proc on Darwin. The equivalent of one /proc/<pid>/maps line is
 * a Mach VM region, obtained with mach_vm_region_recurse() so that submaps
 * (which iOS uses heavily) are descended into.
 *
 * Field mapping:
 *
 *   mach region        struct vm_area
 *   ------------       --------------
 *   address .. +size   start .. end
 *   info.offset        offset      (offset inside the backing vnode/cache)
 *   info.protection    perm[0..2]
 *   info.share_mode    perm[3]     ('p' private, 's' shared)
 *   proc_regionfilename(pid, addr)  pathname
 *
 * dev/inode have no Mach counterpart and stay zero; nothing downstream reads
 * them, they only exist because /proc supplies them on Linux.
 *
 * Regions come back in ascending address order, which the classifier relies
 * on for segment numbering.
 */

#include "platform/plat_proc.h"

#if defined(__APPLE__)

#include <errno.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/types.h>

#include <mach/mach.h>
#include <mach/vm_region.h>
#include <mach/vm_statistics.h>

#include "platform/plat_mach.h"
#include "vma/vm_area.h"

/*
 * proc_regionfilename() is what turns a Mach region into a pathname, and it
 * lives in libproc. <libproc.h> is a macOS header: the iPhoneOS SDK does not
 * ship it, even though libSystem exports the function on the device too (it is
 * listed in the SDK's libSystem.tbd). macOS, the simulator SDK and the
 * tests/apple-stub tree apple-check compiles against all have the header; where
 * it is missing, the prototype is declared here, exactly as the header has it.
 */
#if defined(__has_include)
#if __has_include(<libproc.h>)
#include <libproc.h>
#define PTRSCAN_HAVE_LIBPROC_H 1
#endif
#endif

#ifndef PTRSCAN_HAVE_LIBPROC_H
extern int proc_regionfilename(int pid, uint64_t address,
                               void *buffer, uint32_t buffersize);
#endif

/* proc_regionfilename() needs room for a full bundle-container path. */
#define PLAT_PATH_MAX 1024

/*
 * Bounds for the region walk. A real map nests a few submaps deep and holds a
 * few thousand regions; these exist only so that a kernel reporting something
 * unexpected cannot spin the scanner forever.
 */
#define PLAT_MAPS_MAX_DEPTH      32u
#define PLAT_MAPS_MAX_ITERATIONS (1u << 20)

/*
 * Walk tracing, off unless PTRSCAN_DEBUG_MAPS is set in the environment.
 *
 * On a jailbroken device there is no debugger to attach to, and a map read
 * that never returns looks exactly like one that is merely slow: the process
 * burns CPU, allocates nothing and prints nothing. The trace says which call
 * it is sitting in.
 */
static int maps_trace_on(void)
{
    static int on = -1;

    if (on < 0)
        on = (getenv("PTRSCAN_DEBUG_MAPS") != NULL);
    return on;
}

static void maps_trace(const char *fmt, ...)
{
    va_list ap;

    if (!maps_trace_on())
        return;

    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fflush(stderr);
}

/*
 * Watchdog around mach_vm_region_recurse().
 *
 * On iOS 15 a game's map made that call spin inside the kernel: no return, no
 * allocation, 100% CPU, for as long as it was left running (see the committed
 * notes). Nothing in user space can fix a kernel loop, so the call gets a
 * deadline: if it does not answer, the walk falls back to the non-recursive
 * mach_vm_region() for that address -- a plain lookup with no submap descent
 * to get stuck in -- and carries on. The price is coarser regions (top-level
 * entries instead of the submaps' contents) for the range that stalled.
 *
 * parse_maps() runs before any thread is started, which is what makes
 * siglongjmp() out of the handler safe here; the timeout is tunable through
 * PTRSCAN_MAPS_TIMEOUT_MS (0 disables the watchdog).
 */
#define PLAT_WALK_TIMEOUT_MS 5000L

static sigjmp_buf            g_walk_jmp;
static volatile sig_atomic_t g_walk_stalled;

static void walk_stalled(int sig)
{
    (void)sig;
    g_walk_stalled = 1;
    siglongjmp(g_walk_jmp, 1);
}

static long walk_timeout_ms(void)
{
    static long ms = -1;

    if (ms < 0) {
        const char *env = getenv("PTRSCAN_MAPS_TIMEOUT_MS");
        char *end = NULL;
        long v = env ? strtol(env, &end, 0) : PLAT_WALK_TIMEOUT_MS;

        ms = (env && end && *end == '\0' && v >= 0) ? v : PLAT_WALK_TIMEOUT_MS;
    }
    return ms;
}

static void walk_timer(long ms)
{
    struct itimerval it;

    memset(&it, 0, sizeof(it));
    if (ms > 0) {
        it.it_value.tv_sec  = ms / 1000;
        it.it_value.tv_usec = (ms % 1000) * 1000;
    }
    setitimer(ITIMER_REAL, &it, NULL);
}

/*
 * mach_vm_region_recurse() with a deadline. `*stalled` is set when the call
 * was abandoned; the caller then answers the same question with the
 * non-recursive call instead.
 */
static kern_return_t recurse_with_deadline(mach_port_t task,
                                           mach_vm_address_t *addr,
                                           mach_vm_size_t *size,
                                           natural_t *depth,
                                           vm_region_submap_info_data_64_t *info,
                                           mach_msg_type_number_t *count,
                                           int *stalled)
{
    struct sigaction sa, old;
    kern_return_t kr;
    long ms = walk_timeout_ms();

    *stalled = 0;

    if (ms <= 0)
        return mach_vm_region_recurse(task, addr, size, depth,
                                      (vm_region_recurse_info_t)info, count);

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = walk_stalled;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGALRM, &sa, &old);

    if (sigsetjmp(g_walk_jmp, 1) == 0) {
        walk_timer(ms);
        kr = mach_vm_region_recurse(task, addr, size, depth,
                                    (vm_region_recurse_info_t)info, count);
        walk_timer(0);
    } else {
        *stalled = 1;
        kr = KERN_FAILURE;
    }

    sigaction(SIGALRM, &old, NULL);
    return kr;
}

/*
 * Share modes are documented in <mach/vm_region.h>. Fall back to the numeric
 * values if an SDK revision does not export the names.
 */
#ifndef SM_COW
#define SM_COW 1
#endif
#ifndef SM_PRIVATE
#define SM_PRIVATE 2
#endif
#ifndef SM_SHARED
#define SM_SHARED 4
#endif
#ifndef SM_TRUESHARED
#define SM_TRUESHARED 5
#endif
#ifndef SM_SHARED_ALIASED
#define SM_SHARED_ALIASED 7
#endif

static void protection_to_perm(uint32_t prot, uint8_t share_mode, char *perm)
{
    perm[0] = (prot & VM_PROT_READ)    ? 'r' : '-';
    perm[1] = (prot & VM_PROT_WRITE)   ? 'w' : '-';
    perm[2] = (prot & VM_PROT_EXECUTE) ? 'x' : '-';

    switch (share_mode) {
    case SM_SHARED:
    case SM_TRUESHARED:
    case SM_SHARED_ALIASED:
        perm[3] = 's';
        break;
    default:
        /* SM_COW, SM_PRIVATE, SM_PRIVATE_ALIASED, SM_EMPTY, SM_LARGE_PAGE */
        perm[3] = 'p';
        break;
    }
    perm[4] = '\0';
}

int plat_proc_maps(pid_t pid, struct vm_area **vm_area_out)
{
    if (!vm_area_out)
        return -EINVAL;

    *vm_area_out = NULL;

    mach_port_t task = plat_mach_task(pid);
    if (task == MACH_PORT_NULL)
        return -(errno ? errno : EPERM);

    maps_trace("maps: pid %d -> task port %u\n", (int)pid, (unsigned)task);

    struct vm_area *head = NULL, *tail = NULL;
    mach_vm_address_t addr = 0;
    natural_t depth = 0;
    uint64_t iterations = 0;
    int region_count = 0;
    int fallbacks = 0;
    int ret = 0;

    for (;;) {
        mach_vm_size_t size = 0;
        vm_region_submap_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

        if (++iterations > PLAT_MAPS_MAX_ITERATIONS) {
            ret = -ELOOP;
            break;
        }

        memset(&info, 0, sizeof(info));

        /*
         * The call writes the start of the region it found back into `addr`,
         * and for a submap that is the start of the range the submap is mapped
         * over -- *behind* the address we asked about. Remember what we asked
         * for: that, not the returned address, is where the descent below has
         * to continue.
         */
        mach_vm_address_t wanted = addr;
        int verbose = maps_trace_on() &&
                      (iterations <= 40 || (iterations % 1000) == 0);

        if (verbose)
            maps_trace("maps #%llu: recurse(req=0x%llx depth=%u)\n",
                       (unsigned long long)iterations,
                       (unsigned long long)wanted, (unsigned)depth);

        int stalled = 0;

        kern_return_t kr = recurse_with_deadline(task, &addr, &size, &depth,
                                                 &info, &count, &stalled);

        if (stalled) {
            /*
             * The recursive call never came back for this address. Ask the
             * non-recursive one, which reports the top-level entry that covers
             * it, and treat that entry as a region: descending into it is
             * exactly what stalls, so it is reported whole and the walk moves
             * past it.
             */
            vm_region_basic_info_data_64_t basic;
            mach_msg_type_number_t bcount = VM_REGION_BASIC_INFO_COUNT_64;
            mach_vm_address_t faddr = wanted;

            memset(&basic, 0, sizeof(basic));

            kr = mach_vm_region(task, &faddr, &size, VM_REGION_BASIC_INFO_64,
                                (vm_region_info_t)&basic, &bcount, NULL);
            if (kr != KERN_SUCCESS)
                break;

            addr = faddr;
            memset(&info, 0, sizeof(info));
            info.protection = basic.protection;
            info.share_mode = basic.shared ? SM_SHARED : SM_PRIVATE;
            info.offset     = basic.offset;
            info.is_submap  = 0;

            if (fallbacks++ == 0)
                fprintf(stderr,
                        "warn: mach_vm_region_recurse() did not answer within "
                        "%ld ms at 0x%llx; using coarser regions from "
                        "mach_vm_region() from there on\n",
                        walk_timeout_ms(), (unsigned long long)wanted);
        }

        if (verbose)
            maps_trace("maps #%llu:   -> kr=%d addr=0x%llx size=%llu depth=%u "
                       "submap=%d\n",
                       (unsigned long long)iterations, (int)kr,
                       (unsigned long long)addr, (unsigned long long)size,
                       (unsigned)depth, (int)info.is_submap);
        if (kr == KERN_INVALID_ADDRESS)
            break;                      /* past the last region: done */
        if (kr != KERN_SUCCESS) {
            ret = -plat_mach_errno(kr);
            break;
        }
        if (size == 0)                  /* defensive: never loop forever */
            break;

        if (info.is_submap) {
            /*
             * Descend one level, at the address we asked about. Descending
             * from the submap's own start instead would answer with the first
             * region of that submap on every pass, so the walk would re-read
             * one region forever and never reach the end of the map.
             */
            if (depth >= PLAT_MAPS_MAX_DEPTH)
                break;                  /* deeper than any real map: stop */
            depth++;
            addr = wanted;
            continue;
        }

        struct vm_area *node = calloc(1, sizeof(*node));
        if (!node) {
            ret = -ENOMEM;
            break;
        }

        node->start  = (uint64_t)addr;
        node->end    = (uint64_t)addr + (uint64_t)size;
        node->offset = (off_t)info.offset;
        node->dev    = 0;
        node->inode  = 0;
        protection_to_perm(info.protection, (uint8_t)info.share_mode,
                           node->perm);

        char path[PLAT_PATH_MAX];

        if (region_count < 20)
            maps_trace("maps:   region %d at 0x%llx, asking for its path\n",
                       region_count, (unsigned long long)addr);

        int plen = proc_regionfilename((int)pid, (uint64_t)addr,
                                       path, (uint32_t)sizeof(path));

        if (region_count < 20)
            maps_trace("maps:   region %d path len %d\n", region_count, plen);
        if (plen > 0) {
            path[sizeof(path) - 1] = '\0';
            node->pathname = strdup(path);
            if (!node->pathname) {
                free(node);
                ret = -ENOMEM;
                break;
            }
        }

        node->next = NULL;
        if (!head) head = tail = node;
        else { tail->next = node; tail = node; }
        region_count++;

        addr += size;
        depth = 0;                      /* next lookup starts at the top level */
    }

    if (ret != 0) {
        free_vm_area(head);
        return ret;
    }

    *vm_area_out = head;
    return 0;
}

#endif /* __APPLE__ */
