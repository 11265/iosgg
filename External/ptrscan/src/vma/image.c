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

#include "vma/image.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ------------------------------------------------------------------ ELF --- */

#define EI_NIDENT    16
#define ELFCLASS32   1
#define ELFCLASS64   2
#define ELFDATA2LSB  1

#define PT_LOAD      1

#define PF_X         1
#define PF_W         2

#define ELF_MAX_PHNUM 1024

struct elf32_ehdr {
    unsigned char e_ident[EI_NIDENT];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint32_t e_entry;
    uint32_t e_phoff;
    uint32_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} __attribute__((packed));

struct elf64_ehdr {
    unsigned char e_ident[EI_NIDENT];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint64_t e_entry;
    uint64_t e_phoff;
    uint64_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} __attribute__((packed));

struct elf32_phdr {
    uint32_t p_type;
    uint32_t p_offset;
    uint32_t p_vaddr;
    uint32_t p_paddr;
    uint32_t p_filesz;
    uint32_t p_memsz;
    uint32_t p_flags;
    uint32_t p_align;
} __attribute__((packed));

struct elf64_phdr {
    uint32_t p_type;
    uint32_t p_flags;
    uint64_t p_offset;
    uint64_t p_vaddr;
    uint64_t p_paddr;
    uint64_t p_filesz;
    uint64_t p_memsz;
    uint64_t p_align;
} __attribute__((packed));

/* --------------------------------------------------------------- Mach-O --- */

#define MH_MAGIC_64      0xfeedfacfu
#define MH_CIGAM_64      0xcffaedfeu
#define FAT_MAGIC        0xcafebabeu
#define FAT_MAGIC_64     0xcafebabfu

#define LC_SEGMENT_64    0x19u

#define CPU_TYPE_X86_64  0x01000007u
#define CPU_TYPE_ARM64   0x0100000cu

#define VM_PROT_WRITE    0x2u
#define VM_PROT_EXECUTE  0x4u

#define IMG_MAX_CMDS     4096u
#define IMG_MAX_CMDS_SZ  (1024u * 1024u)
#define FAT_MAX_ARCHS    64u

struct mach_header_64 {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint32_t reserved;
};

struct load_command {
    uint32_t cmd;
    uint32_t cmdsize;
};

struct segment_command_64 {
    uint32_t cmd;
    uint32_t cmdsize;
    char     segname[16];
    uint64_t vmaddr;
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    uint32_t maxprot;
    uint32_t initprot;
    uint32_t nsects;
    uint32_t flags;
};

/* ------------------------------------------------------------- sources --- */

static int src_read(const struct img_src *src, uint64_t off,
                    void *dst, size_t len)
{
    if (len == 0)
        return 0;
    return src->read(src->ctx, off, dst, len);
}

struct img_mem_ctx {
    const uint8_t *data;
    size_t         len;
};

static int mem_read(void *ctx, uint64_t off, void *dst, size_t len)
{
    const struct img_mem_ctx *m = ctx;

    if (off > (uint64_t)m->len)
        return -1;
    if (len > (size_t)m->len - (size_t)off)
        return -1;

    memcpy(dst, m->data + (size_t)off, len);
    return 0;
}

static int file_read(void *ctx, uint64_t off, void *dst, size_t len)
{
    int      fd = *(int *)ctx;
    uint8_t *p  = dst;

    while (len > 0) {
        ssize_t n = pread(fd, p, len, (off_t)off);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        if (n == 0)
            return -1;

        p   += n;
        off += (uint64_t)n;
        len -= (size_t)n;
    }
    return 0;
}

/* ---------------------------------------------------------- byte order --- */

static uint32_t rd_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
}

static uint64_t rd_be64(const uint8_t *p)
{
    return ((uint64_t)rd_be32(p) << 32) | (uint64_t)rd_be32(p + 4);
}

/* ------------------------------------------------------- image parsing --- */

static int parse_image(const struct img_src *src, uint64_t base_off,
                       struct img_meta *out, int depth);

static int parse_elf(const struct img_src *src, uint64_t base_off,
                     struct img_meta *out)
{
    unsigned char ident[EI_NIDENT];

    if (src_read(src, base_off, ident, sizeof(ident)) != 0)
        return -1;
    if (ident[0] != 0x7f || ident[1] != 'E' ||
        ident[2] != 'L'  || ident[3] != 'F')
        return -1;
    if (ident[5] != ELFDATA2LSB)
        return -1;

    int k = 0;

    if (ident[4] == ELFCLASS64) {
        struct elf64_ehdr eh;

        if (src_read(src, base_off, &eh, sizeof(eh)) != 0)
            return -1;
        if (eh.e_phentsize != sizeof(struct elf64_phdr))
            return -1;
        if (eh.e_phnum == 0 || eh.e_phnum > ELF_MAX_PHNUM)
            return -1;

        for (uint16_t i = 0; i < eh.e_phnum && k < IMG_MAX_SEGS; i++) {
            struct elf64_phdr ph;
            uint64_t poff = base_off + eh.e_phoff +
                            (uint64_t)i * sizeof(ph);

            if (src_read(src, poff, &ph, sizeof(ph)) != 0)
                return -1;
            if (ph.p_type != PT_LOAD || ph.p_filesz == 0)
                continue;

            out->segs[k].vaddr  = ph.p_vaddr;
            out->segs[k].offset = base_off + ph.p_offset;
            out->segs[k].filesz = ph.p_filesz;
            out->segs[k].memsz  = ph.p_memsz < ph.p_filesz
                                  ? ph.p_filesz : ph.p_memsz;
            out->segs[k].flags  = 0;
            if (ph.p_flags & PF_X) out->segs[k].flags |= IMG_FLAG_X;
            if (ph.p_flags & PF_W) out->segs[k].flags |= IMG_FLAG_W;
            k++;
        }
    } else if (ident[4] == ELFCLASS32) {
        struct elf32_ehdr eh;

        if (src_read(src, base_off, &eh, sizeof(eh)) != 0)
            return -1;
        if (eh.e_phentsize != sizeof(struct elf32_phdr))
            return -1;
        if (eh.e_phnum == 0 || eh.e_phnum > ELF_MAX_PHNUM)
            return -1;

        for (uint16_t i = 0; i < eh.e_phnum && k < IMG_MAX_SEGS; i++) {
            struct elf32_phdr ph;
            uint64_t poff = base_off + eh.e_phoff +
                            (uint64_t)i * sizeof(ph);

            if (src_read(src, poff, &ph, sizeof(ph)) != 0)
                return -1;
            if (ph.p_type != PT_LOAD || ph.p_filesz == 0)
                continue;

            out->segs[k].vaddr  = ph.p_vaddr;
            out->segs[k].offset = base_off + ph.p_offset;
            out->segs[k].filesz = ph.p_filesz;
            out->segs[k].memsz  = ph.p_memsz < ph.p_filesz
                                  ? ph.p_filesz : ph.p_memsz;
            out->segs[k].flags  = 0;
            if (ph.p_flags & PF_X) out->segs[k].flags |= IMG_FLAG_X;
            if (ph.p_flags & PF_W) out->segs[k].flags |= IMG_FLAG_W;
            k++;
        }
    } else {
        return -1;
    }

    if (k == 0)
        return -1;

    out->ok    = 1;
    out->nsegs = k;
    return 0;
}

static int parse_macho(const struct img_src *src, uint64_t base_off,
                       struct img_meta *out)
{
    struct mach_header_64 mh;

    if (src_read(src, base_off, &mh, sizeof(mh)) != 0)
        return -1;
    if (mh.magic != MH_MAGIC_64)
        return -1;
    if (mh.ncmds == 0 || mh.ncmds > IMG_MAX_CMDS)
        return -1;
    if (mh.sizeofcmds == 0 || mh.sizeofcmds > IMG_MAX_CMDS_SZ)
        return -1;

    uint64_t total = (uint64_t)sizeof(mh) + (uint64_t)mh.sizeofcmds;
    uint8_t *buf = malloc((size_t)total);
    if (!buf)
        return -1;

    if (src_read(src, base_off, buf, (size_t)total) != 0) {
        free(buf);
        return -1;
    }

    const uint8_t *cmds = buf + sizeof(struct mach_header_64);
    uint32_t off = 0;
    int k = 0;

    for (uint32_t i = 0; i < mh.ncmds && off < mh.sizeofcmds; i++) {
        const struct load_command *lc;
        const struct segment_command_64 *sc;

        if ((uint64_t)off + sizeof(struct load_command) > mh.sizeofcmds)
            break;

        lc = (const struct load_command *)(cmds + off);
        if (lc->cmdsize < sizeof(struct load_command))
            break;
        if ((uint64_t)off + lc->cmdsize > mh.sizeofcmds)
            break;

        if (lc->cmd == LC_SEGMENT_64 &&
            lc->cmdsize >= sizeof(struct segment_command_64)) {
            sc = (const struct segment_command_64 *)lc;

            /*
             * Segments with no file backing are skipped. That drops
             * __PAGEZERO (a 4 GB protection hole with no mapping) while
             * keeping __DATA, whose .bss tail is the interesting part.
             */
            if (sc->filesize > 0 && k < IMG_MAX_SEGS) {
                out->segs[k].vaddr  = sc->vmaddr;
                out->segs[k].offset = base_off + sc->fileoff;
                out->segs[k].filesz = sc->filesize;
                out->segs[k].memsz  = sc->vmsize < sc->filesize
                                      ? sc->filesize : sc->vmsize;
                out->segs[k].flags  = 0;
                if (sc->initprot & VM_PROT_EXECUTE)
                    out->segs[k].flags |= IMG_FLAG_X;
                if (sc->initprot & VM_PROT_WRITE)
                    out->segs[k].flags |= IMG_FLAG_W;
                k++;
            }
        }

        off += lc->cmdsize;
    }

    free(buf);

    if (k == 0)
        return -1;

    out->ok    = 1;
    out->nsegs = k;
    return 0;
}

static int parse_fat(const struct img_src *src, uint64_t base_off,
                     struct img_meta *out, int depth)
{
    uint8_t hdr[8];
    uint32_t nfat;

    if (src_read(src, base_off, hdr, sizeof(hdr)) != 0)
        return -1;

    uint32_t magic = rd_be32(hdr);
    int is64 = (magic == FAT_MAGIC_64);
    if (!is64 && magic != FAT_MAGIC)
        return -1;

    nfat = rd_be32(hdr + 4);
    if (nfat == 0 || nfat > FAT_MAX_ARCHS)
        return -1;

    uint32_t entry = is64 ? 32u : 20u;
    uint64_t best_off = 0;
    int best_rank = 99;
    int found = 0;

    for (uint32_t i = 0; i < nfat; i++) {
        uint8_t a[32];
        uint64_t off;
        uint32_t cputype;

        if (src_read(src, base_off + 8 + (uint64_t)i * entry, a, entry) != 0)
            return -1;

        cputype = rd_be32(a);
        if (is64) {
            off = rd_be64(a + 8);
        } else {
            off = rd_be32(a + 8);
        }

        /* Prefer an arm64 slice, then x86_64 (simulator), then anything. */
        int rank = 2;
        if (cputype == CPU_TYPE_ARM64)
            rank = 0;
        else if (cputype == CPU_TYPE_X86_64)
            rank = 1;

        if (rank < best_rank) {
            best_rank = rank;
            best_off  = off;
            found     = 1;
        }

        if (best_rank == 0)
            break;
    }

    if (!found)
        return -1;

    return parse_image(src, base_off + best_off, out, depth + 1);
}

static int parse_image(const struct img_src *src, uint64_t base_off,
                       struct img_meta *out, int depth)
{
    uint8_t magic[4];

    if (depth > 2)
        return -1;

    if (src_read(src, base_off, magic, sizeof(magic)) != 0)
        return -1;

    /* Compared byte-wise so the parser does not assume a host byte order. */
    if (magic[0] == 0x7f && magic[1] == 'E' &&
        magic[2] == 'L'  && magic[3] == 'F')
        return parse_elf(src, base_off, out);
    if (magic[0] == 0xcf && magic[1] == 0xfa &&
        magic[2] == 0xed && magic[3] == 0xfe)
        return parse_macho(src, base_off, out);
    /* FAT_MAGIC (ca fe ba be) and FAT_MAGIC_64 (ca fe ba bf). */
    if (magic[0] == 0xca && magic[1] == 0xfe && magic[2] == 0xba &&
        (magic[3] == 0xbe || magic[3] == 0xbf))
        return parse_fat(src, base_off, out, depth);

    return -1;
}

/* -------------------------------------------------------------- public --- */

int img_parse_src(const struct img_src *src, struct img_meta *out)
{
    if (!src || !src->read || !out)
        return -1;

    memset(out, 0, sizeof(*out));
    return parse_image(src, 0, out, 0);
}

int img_parse(const void *buf, size_t len, struct img_meta *out)
{
    struct img_mem_ctx ctx;
    struct img_src     src;

    if (!buf || !out)
        return -1;

    ctx.data = buf;
    ctx.len  = len;
    src.ctx  = &ctx;
    src.read = mem_read;

    return img_parse_src(&src, out);
}

int img_parse_file(const char *path, struct img_meta *out)
{
    if (!path || !out)
        return -1;

    /*
     * O_NONBLOCK because `path` usually comes from a process memory map, so it
     * can name a FIFO or another special file: a blocking open() on a FIFO with
     * no writer would hang the scanner. It is ignored for regular files.
     */
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0)
        return -1;

    struct img_src src;
    src.ctx  = &fd;
    src.read = file_read;

    int rc = img_parse_src(&src, out);
    close(fd);
    return rc;
}

const struct img_seg *img_seg_at_offset(const struct img_meta *m,
                                        uint64_t file_off)
{
    if (!m || !m->ok)
        return NULL;

    for (int i = 0; i < m->nsegs; i++) {
        const struct img_seg *s = &m->segs[i];
        if (file_off >= s->offset && file_off < s->offset + s->filesz)
            return s;
    }
    return NULL;
}

int img_bias_at(const struct img_meta *m, uint64_t addr, uint64_t file_off,
                uint64_t *bias_out)
{
    const struct img_seg *s = img_seg_at_offset(m, file_off);
    if (!s || !bias_out)
        return -1;

    *bias_out = addr - (s->vaddr + (file_off - s->offset));
    return 0;
}

const struct img_seg *img_seg_covering(const struct img_meta *m, uint64_t bias,
                                       uint64_t addr, int *zero_fill)
{
    if (!m || !m->ok)
        return NULL;

    for (int i = 0; i < m->nsegs; i++) {
        const struct img_seg *s = &m->segs[i];
        uint64_t start = bias + s->vaddr;
        uint64_t end   = start + s->memsz;

        if (addr < start || addr >= end)
            continue;

        if (zero_fill)
            *zero_fill = (addr >= start + s->filesz) ? 1 : 0;
        return s;
    }

    if (zero_fill)
        *zero_fill = 0;
    return NULL;
}
