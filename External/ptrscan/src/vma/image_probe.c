/*
 * Copyright (C) 2026 kaidev
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation: version 3 of the License.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * Image header probe against a live process.
 *
 * The reader callback is the same one the index builder uses, so the probe
 * works with any memory backend (Mach VM on iOS, process_vm_readv on Linux)
 * and can be unit tested with a synthetic reader.
 */

#include "vma/image.h"

#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/uio.h>

/*
 * Read up to `len` bytes at `addr`, allowing the backend to return a short
 * count at a page boundary. Returns the number of bytes read.
 */
static size_t read_at(pid_t pid, fs_ptrscan_process_reader_t reader,
                      void *userdata, uint64_t addr, void *dst, size_t len)
{
    size_t done = 0;

    while (done < len) {
        struct iovec local;
        struct iovec remote;

        local.iov_base  = (char *)dst + done;
        local.iov_len   = len - done;
        remote.iov_base = (void *)(uintptr_t)(addr + done);
        remote.iov_len  = len - done;

        ssize_t n = reader(pid, &local, 1, &remote, 1, userdata);
        if (n <= 0)
            break;

        done += (size_t)n;
        if ((size_t)n < local.iov_len)
            break;                      /* short read: stop at the hole */
    }

    return done;
}

struct img_probe_ctx {
    pid_t                       pid;
    fs_ptrscan_process_reader_t reader;
    void                       *userdata;
    uint64_t                    base;
};

static int probe_read(void *ctx, uint64_t off, void *dst, size_t len)
{
    struct img_probe_ctx *p = ctx;

    if (off > UINT64_MAX - p->base)
        return -1;

    size_t got = read_at(p->pid, p->reader, p->userdata,
                         p->base + off, dst, len);
    return got == len ? 0 : -1;
}

int img_probe_process(pid_t pid, fs_ptrscan_process_reader_t reader,
                      void *userdata, uint64_t addr, struct img_meta *out)
{
    if (!reader || !out)
        return -1;

    struct img_probe_ctx ctx;
    ctx.pid      = pid;
    ctx.reader   = reader;
    ctx.userdata = userdata;
    ctx.base     = addr;

    struct img_src src;
    src.ctx  = &ctx;
    src.read = probe_read;

    return img_parse_src(&src, out);
}
