#ifndef VMA_SELECT_H
#define VMA_SELECT_H

#include "vma/vm_area.h"

struct vma_select {
    char *module;
    char *perm;
    int seg_type;
    int index;
};

struct vma_select **to_vma_select(const char *const *s, int count);
void free_vma_select(struct vma_select **select, int count);

/*
 * Destructive filters. Each one unlinks and frees the regions it rejects and
 * returns the number of regions kept, or -1 when the arguments are unusable.
 *
 * `vma_filter_select()` keeps only the regions matching at least one spec;
 * `vma_filter_exclude()` drops those instead. `vma_filter_max_region()` drops
 * any single region larger than `max_bytes` (0 = no limit), which is how the
 * mappings a process inherits but no pointer chain needs -- the dyld shared
 * cache on iOS, big PROT_NONE reservations elsewhere -- are kept out of an
 * index: the shared cache is mapped anonymously, so it has no path for
 * `vma_filter_exclude()` to match.
 */
int vma_filter_select(struct vm_area **area, struct vma_select **select, int count);
int vma_filter_exclude(struct vm_area **area, struct vma_select **select, int count);
int vma_filter_max_region(struct vm_area **area, uint64_t max_bytes);

/*
 * Keep only the regions something can be written to. Read-only mappings (the
 * dyld shared cache and the like) cost most of an index build and hold no
 * pointer slot a chain can use, so a phone-sized scan usually wants this.
 */
int vma_filter_writable(struct vm_area **area);

#endif  /* VMA_SELECT_H */