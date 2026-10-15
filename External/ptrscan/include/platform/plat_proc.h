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
 * Platform process access.
 *
 * Everything that differs between the supported targets lives behind these
 * entry points:
 *
 *   Linux / Android : /proc/<pid>/maps  + process_vm_readv(2)
 *   Apple / iOS     : Mach VM regions   + mach_vm_read_overwrite(2)
 *
 * plat_proc_readv() keeps the exact process_vm_readv(2) contract, so the
 * index builder does not need to know which implementation it is talking to:
 * it returns the number of bytes copied, which may be shorter than requested
 * when the tail of the remote range is not readable, or -1 with errno set
 * when nothing could be read.
 */

#ifndef PTRSCAN_PLAT_PROC_H
#define PTRSCAN_PLAT_PROC_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/uio.h>

struct vm_area;

/*
 * Enumerate the mapped regions of `pid` into a freshly allocated
 * `struct vm_area` list, sorted by ascending start address.
 *
 * Returns 0 on success, or a negative errno value on failure.
 * The caller releases the list with free_vm_area().
 */
int plat_proc_maps(pid_t pid, struct vm_area **out);

/*
 * Copy remote memory of `pid` into local memory.
 *
 * Same contract as process_vm_readv(2).
 */
ssize_t plat_proc_readv(pid_t pid,
                        const struct iovec *local_iov, unsigned long liovcnt,
                        const struct iovec *remote_iov, unsigned long riovcnt);

/*
 * Drop any cached per-process handle (on Apple: the task port). Safe to call
 * for a pid that was never opened.
 */
void plat_proc_release(pid_t pid);

/*
 * One-line explanation of the privilege the current platform needs in order
 * to read another process, printed after a failed memory-map query.
 */
const char *plat_proc_hint(void);

/*
 * Reserve `len` bytes at exactly `addr` in this process and return them, or
 * NULL when that address is not available.
 *
 * The self-test needs a target address that is the same on every run, which
 * ASLR otherwise makes impossible. Nothing that is already mapped is ever
 * replaced: an address in use simply fails.
 */
void *plat_map_fixed(uint64_t addr, size_t len);

#endif /* PTRSCAN_PLAT_PROC_H */
