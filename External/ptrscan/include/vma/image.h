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
 * Executable image headers.
 *
 * A memory region is only meaningful once it is tied back to a segment of the
 * executable image that backs it. Two container formats matter here:
 *
 *   ELF      Linux / Android, including the program headers of a .so
 *   Mach-O   iOS / macOS, including universal (FAT) binaries
 *
 * Both are reduced to the same flat list of loadable segments, so the region
 * classifier never needs to know which one it is looking at.
 *
 * Segment file offsets are always normalised to be *file absolute*: for a
 * Mach-O slice inside a FAT container the slice offset is already folded in.
 * That is what the kernel reports for a mapped region, so the two can be
 * compared directly.
 */

#ifndef PTRSCAN_IMAGE_H
#define PTRSCAN_IMAGE_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#include "callback.h"

#define IMG_MAX_SEGS 64

/* Segment access flags, normalised across ELF (PF_*) and Mach-O (VM_PROT_*). */
#define IMG_FLAG_X 0x1u
#define IMG_FLAG_W 0x2u

struct img_seg {
    uint64_t vaddr;     /* virtual address, relative to the image load bias */
    uint64_t offset;    /* file offset of the segment, container absolute */
    uint64_t filesz;    /* bytes backed by the file */
    uint64_t memsz;     /* bytes present in memory (>= filesz) */
    uint32_t flags;     /* IMG_FLAG_* */
};

struct img_meta {
    int          ok;
    int          nsegs;
    struct img_seg segs[IMG_MAX_SEGS];
};

/*
 * Byte source for the parser: an open file, a memory buffer, or a live
 * process. `read` returns 0 on success and -1 when the range cannot be read.
 */
struct img_src {
    void *ctx;
    int (*read)(void *ctx, uint64_t off, void *dst, size_t len);
};

/* Parse an image whose header sits at offset 0 of `src`. */
int img_parse_src(const struct img_src *src, struct img_meta *out);

/* Parse a memory buffer / a file on disk. */
int img_parse(const void *buf, size_t len, struct img_meta *out);
int img_parse_file(const char *path, struct img_meta *out);

/*
 * Parse an image header that lives inside the address space of `pid`, at
 * address `addr`. Used to classify modules that cannot be trusted on disk:
 * FAT slices, and dylibs served out of the dyld shared cache, whose region
 * file offsets do not line up with the individual Mach-O file.
 */
int img_probe_process(pid_t pid, fs_ptrscan_process_reader_t reader,
                      void *userdata, uint64_t addr, struct img_meta *out);

/* Segment whose file range covers `file_off`, or NULL. */
const struct img_seg *img_seg_at_offset(const struct img_meta *m,
                                        uint64_t file_off);

/*
 * Load bias of an image mapped at `addr`, where the region that starts at
 * `addr` begins at `file_off` inside the image file. Returns 0 on success.
 */
int img_bias_at(const struct img_meta *m, uint64_t addr, uint64_t file_off,
                uint64_t *bias_out);

/*
 * Segment that covers address `addr` given the image load bias, or NULL.
 * Sets `*zero_fill` when the address falls in the .bss tail of the segment.
 */
const struct img_seg *img_seg_covering(const struct img_meta *m, uint64_t bias,
                                       uint64_t addr, int *zero_fill);

#endif /* PTRSCAN_IMAGE_H */
