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
 * Region classification.
 *
 * The platform layer hands back a flat list of mapped regions. To be useful a
 * region has to be tied to the segment of an executable image that backs it,
 * which yields three things the rest of the tool depends on:
 *
 *   seg_type   text / rodata / data / bss, for grouping and for -t selectors
 *   module     the region that carries the image base, so all segments of one
 *              library report the same module
 *   seg_index  the ordinal of this segment among the same module+type, so a
 *              chain can name a segment unambiguously
 *
 * Two providers supply image headers:
 *
 *   1. Live memory, via the process reader. The Mach-O or ELF header is read
 *      from the process itself at each candidate image base. This is the only
 *      way to classify correctly on iOS, where a dylib served from the dyld
 *      shared cache reports shared-cache file offsets that do not match its
 *      own Mach-O file offsets, and where FAT slices are mapped at their
 *      slice offset.
 *   2. On disk, by opening the mapped file. This is what Android uses, and it
 *      remains the fallback when live headers cannot be read.
 *
 * A region is classified by finding the module whose segment ranges cover its
 * start address. The range test uses memsz, not filesz, so the zero-fill tail
 * of a segment is covered too: that is where .bss lives, and on both platforms
 * it shows up as an anonymous writable region right after the file-backed one.
 */

#include "vma/vm_area.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "platform/plat_proc.h"
#include "vma/image.h"

#define VMA_MAX_MODULES 8192
#define VMA_MAX_PATHS   8192

struct vma_module {
    struct img_meta  meta;
    uint64_t         bias;    /* address = bias + seg.vaddr */
    uint64_t         lo;      /* span covered by all segment ranges */
    uint64_t         hi;
    struct vm_area  *root;    /* region carrying the image base */
    int              probed;  /* 1 when the header came from live memory */
};

struct vma_modules {
    struct vma_module *v;
    int                n;
    int                cap;
};

static void module_span(const struct img_meta *m, uint64_t bias,
                        uint64_t *lo_out, uint64_t *hi_out)
{
    uint64_t lo = UINT64_MAX, hi = 0;

    for (int i = 0; i < m->nsegs; i++) {
        uint64_t start = bias + m->segs[i].vaddr;
        uint64_t end   = start + m->segs[i].memsz;

        if (start < lo) lo = start;
        if (end > hi)   hi = end;
    }

    if (lo == UINT64_MAX) {
        lo = 0;
        hi = 0;
    }

    *lo_out = lo;
    *hi_out = hi;
}

static struct vma_module *modules_push(struct vma_modules *set,
                                       const struct img_meta *m,
                                       uint64_t bias, struct vm_area *root,
                                       int probed)
{
    if (set->n >= VMA_MAX_MODULES)
        return NULL;

    if (set->n == set->cap) {
        int nc = set->cap ? set->cap * 2 : 64;
        struct vma_module *nv = realloc(set->v, (size_t)nc * sizeof(*nv));
        if (!nv)
            return NULL;
        set->v   = nv;
        set->cap = nc;
    }

    struct vma_module *mod = &set->v[set->n++];
    mod->meta   = *m;
    mod->bias   = bias;
    mod->root   = root;
    mod->probed = probed;
    module_span(m, bias, &mod->lo, &mod->hi);

    return mod;
}

static int cmp_module(const void *a, const void *b)
{
    const struct vma_module *x = a;
    const struct vma_module *y = b;

    if (x->lo < y->lo) return -1;
    if (x->lo > y->lo) return  1;
    return 0;
}

/* Linear probe, used while the module list is still being built. */
static int module_covers_linear(const struct vma_modules *set, uint64_t addr)
{
    for (int i = 0; i < set->n; i++) {
        if (addr >= set->v[i].lo && addr < set->v[i].hi)
            return 1;
    }
    return 0;
}

/* Binary search over the sorted module list. */
static const struct vma_module *module_find(const struct vma_modules *set,
                                            uint64_t addr)
{
    int lo = 0, hi = set->n - 1, cand = -1;

    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        if (set->v[mid].lo <= addr) {
            cand = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }

    if (cand < 0)
        return NULL;
    if (addr < set->v[cand].hi)
        return &set->v[cand];
    return NULL;
}

/*
 * Do `region` and `module_root` belong to the same mapped file? Anonymous
 * regions (the .bss tail) have no path of their own and are always allowed.
 */
static int region_matches_module(const struct vm_area *region,
                                 const struct vm_area *module_root)
{
    if (!region || !module_root)
        return 0;
    if (!region->pathname || !module_root->pathname)
        return 1;
    return strcmp(region->pathname, module_root->pathname) == 0;
}

/* --------------------------------------------------------- seg_index ---- */

/*
 * Hash table used by the last pass to assign seg_index in O(n).
 *
 * Key: (module pointer, seg_type).
 * The region list is ascending by start address, so a running per-key counter
 * gives the same result as counting the earlier regions of that key.
 */
struct seg_idx_entry {
    struct vm_area *module;
    uint32_t        seg_type;
    uint32_t        count;
    uint8_t         used;
};

static size_t seg_idx_hash(struct vm_area *module, uint32_t seg_type)
{
    uint64_t h = (uint64_t)(uintptr_t)module;
    h ^= (uint64_t)seg_type * 0x9E3779B97F4A7C15ULL;
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33;
    h *= 0xc4ceb9fe1a85ec53ULL;
    h ^= h >> 33;
    return (size_t)h;
}

static uint32_t seg_idx_assign(struct seg_idx_entry *tab, size_t mask,
                               struct vm_area *module, uint32_t seg_type)
{
    size_t i = seg_idx_hash(module, seg_type) & mask;
    for (;;) {
        if (!tab[i].used) {
            tab[i].used     = 1;
            tab[i].module   = module;
            tab[i].seg_type = seg_type;
            tab[i].count    = 1;
            return 0;
        }
        if (tab[i].module == module && tab[i].seg_type == seg_type)
            return tab[i].count++;
        i = (i + 1) & mask;
    }
}

/* ------------------------------------------------------------ public ---- */

int vma_image(struct vm_area *head, pid_t pid,
              fs_ptrscan_process_reader_t reader, void *userdata)
{
    if (!head)
        return -1;

    for (struct vm_area *v = head; v; v = v->next) {
        v->seg_type  = VMA_TYPE_UNKNOWN;
        v->seg_index = 0;
        v->module    = NULL;
    }

    struct vma_modules mods;
    memset(&mods, 0, sizeof(mods));

    /*
     * Pass 1: image headers read straight out of the target process.
     *
     * Only plausible image bases are probed: a region that starts at file
     * offset 0 (the __TEXT of a file-backed image) or that is executable (the
     * header page of a shared-cache dylib, which starts at a shared-cache
     * offset rather than 0). A wrong guess costs one 4-byte read.
     */
    if (reader && pid > 0) {
        for (struct vm_area *v = head; v; v = v->next) {
            if (!v->pathname)
                continue;
            if (v->offset != 0 && v->perm[2] != 'x')
                continue;

            struct img_meta m;
            if (img_probe_process(pid, reader, userdata, v->start, &m) != 0)
                continue;

            uint64_t bias;
            if (img_bias_at(&m, v->start, 0, &bias) != 0)
                bias = v->start;

            modules_push(&mods, &m, bias, v, 1);
        }
    }

    /*
     * Pass 2: images opened from disk, one module per distinct path that the
     * probes above did not already cover. The path table lives on the heap
     * because a full iOS map can carry a thousand distinct images.
     */
    const char **paths = calloc(VMA_MAX_PATHS, sizeof(*paths));
    int          npaths = 0;

    for (struct vm_area *v = head; v; v = v->next) {
        if (!v->pathname)
            continue;
        if (module_covers_linear(&mods, v->start))
            continue;

        int seen = 0;
        for (int i = 0; i < npaths; i++) {
            if (strcmp(paths[i], v->pathname) == 0) {
                seen = 1;
                break;
            }
        }
        if (seen)
            continue;
        if (!paths || npaths >= VMA_MAX_PATHS)
            continue;
        paths[npaths++] = v->pathname;

        /* Base region: lowest file offset, i.e. the start of the image. */
        struct vm_area *base = v;
        for (struct vm_area *w = head; w; w = w->next) {
            if (!w->pathname || strcmp(w->pathname, v->pathname) != 0)
                continue;
            if (w->offset < base->offset)
                base = w;
        }

        struct img_meta m;
        if (img_parse_file(base->pathname, &m) != 0)
            continue;

        uint64_t bias;
        if (img_bias_at(&m, base->start, (uint64_t)base->offset, &bias) != 0)
            bias = base->start - (uint64_t)base->offset;

        /* Module root: the region that opens the executable segment. */
        struct vm_area *root = NULL;
        for (struct vm_area *w = head; w && !root; w = w->next) {
            if (!w->pathname || strcmp(w->pathname, v->pathname) != 0)
                continue;

            int zero_fill = 0;
            const struct img_seg *s =
                img_seg_covering(&m, bias, w->start, &zero_fill);
            if (s && (s->flags & IMG_FLAG_X))
                root = w;
        }
        if (!root)
            root = base;

        modules_push(&mods, &m, bias, root, 0);
    }

    /* Pass 3: classify every region against the module that covers it. */
    if (mods.n > 1)
        qsort(mods.v, (size_t)mods.n, sizeof(*mods.v), cmp_module);

    for (struct vm_area *v = head; v; v = v->next) {
        const struct vma_module *mod = module_find(&mods, v->start);
        if (!mod)
            continue;
        if (!region_matches_module(v, mod->root))
            continue;

        int zero_fill = 0;
        const struct img_seg *s =
            img_seg_covering(&mod->meta, mod->bias, v->start, &zero_fill);
        if (!s)
            continue;

        uint32_t type;
        if (s->flags & IMG_FLAG_X)
            type = VMA_TYPE_TEXT;
        else if (!(s->flags & IMG_FLAG_W))
            type = VMA_TYPE_RODATA;
        else
            type = VMA_TYPE_DATA;

        if (zero_fill && v->perm[1] == 'w')
            type = VMA_TYPE_BSS;

        v->seg_type = type;
        v->module   = mod->root;
    }

    /*
     * Pass 4: number the segments of each (module, type) pair in ascending
     * address order.
     */
    {
        size_t n = 0;
        for (struct vm_area *v = head; v; v = v->next)
            n++;

        size_t cap = 16;
        while (cap < n * 2)
            cap <<= 1;
        size_t mask = cap - 1;

        struct seg_idx_entry *tab = calloc(cap, sizeof(*tab));
        if (tab) {
            for (struct vm_area *v = head; v; v = v->next) {
                if (v->seg_type == VMA_TYPE_UNKNOWN || !v->module) {
                    v->seg_index = 0;
                    continue;
                }
                v->seg_index = seg_idx_assign(tab, mask, v->module, v->seg_type);
            }
            free(tab);
        } else {
            /* Out of memory: degrade gracefully by zeroing all indices. */
            for (struct vm_area *v = head; v; v = v->next)
                v->seg_index = 0;
        }
    }

    free(paths);
    free(mods.v);
    return 0;
}

int vma_elf(struct vm_area *head)
{
    return vma_image(head, 0, NULL, NULL);
}

int parse_maps(pid_t pid, struct vm_area **vm_area_out)
{
    return plat_proc_maps(pid, vm_area_out);
}

void free_vm_area(struct vm_area *head)
{
    while (head) {
        struct vm_area *next = head->next;
        free(head->pathname);
        free(head);
        head = next;
    }
}

struct vm_area *vm_area_copy(const struct vm_area *src)
{
    if (!src) return NULL;

    struct vm_area *head = NULL, *tail = NULL;

    for (const struct vm_area *cur = src; cur; cur = cur->next) {
        struct vm_area *node = malloc(sizeof(struct vm_area));
        if (!node) {
            while (head) {
                struct vm_area *tmp = head;
                head = head->next;
                free(tmp->pathname);
                free(tmp);
            }
            return NULL;
        }

        *node = *cur;
        node->next = NULL;
        node->module = NULL;

        if (cur->pathname) {
            size_t len = strlen(cur->pathname) + 1;
            node->pathname = malloc(len);
            if (!node->pathname) {
                free(node);
                while (head) {
                    struct vm_area *tmp = head;
                    head = head->next;
                    free(tmp->pathname);
                    free(tmp);
                }
                return NULL;
            }
            memcpy(node->pathname, cur->pathname, len);
        } else {
            node->pathname = NULL;
        }

        if (!head) {
            head = tail = node;
        } else {
            tail->next = node;
            tail = node;
        }
    }

    return head;
}

struct vm_list *vma_copy2_vm(const struct vm_area *src)
{
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0)
        return NULL;

    struct vm_list *head = NULL, *tail = NULL;
    struct vm_list *current = NULL;

    for (const struct vm_area *vma = src; vma; vma = vma->next) {
        uint64_t start = vma->start;
        uint64_t end   = vma->end;

        for (uint64_t addr = start; addr < end; addr += (uint64_t)page_size) {
            if (!current || current->used == VM_LIST_CAPACITY) {
                struct vm_list *node = calloc(1, sizeof(*node));
                if (!node) {
                    while (head) {
                        struct vm_list *tmp = head;
                        head = head->next;
                        free(tmp);
                    }
                    return NULL;
                }
                if (!head) {
                    head = tail = node;
                } else {
                    tail->next = node;
                    tail = node;
                }
                current = node;
            }

            current->addr[current->used++] = addr;
        }
    }

    return head;
}
