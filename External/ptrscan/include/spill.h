#ifndef PTRSCAN_SPILL_H
#define PTRSCAN_SPILL_H

#include <stddef.h>

/*
 * File-backed scratch for the allocations that dominate a run: the index entry
 * array (the biggest thing a build allocates) and the temporary copy the radix
 * sort needs.
 *
 * With PTRSCAN_LOW_MEMORY set they live in a file (PTRSCAN_SPILL_DIR, /tmp by
 * default) mapped MAP_SHARED, so the kernel can write them back and evict the
 * pages at will. Anonymous memory cannot be taken back that way, and on iOS
 * holding too much of it is what gets the process -- or the game being scanned
 * -- killed. The files are unlinked the moment they are created, so a crash
 * leaves nothing behind.
 *
 * Every allocation here is a mapping, which is why releasing one is always
 * spill_release()/spill_unmap() and never free().
 */
struct spill {
    void  *p;
    size_t len;
};

/* Is PTRSCAN_LOW_MEMORY set? Asked once, then cached. */
int spill_wanted(void);

/* File-backed when asked for, anonymous otherwise; p is NULL on failure. */
struct spill spill_alloc(size_t bytes);

/* A read-only mapping of an open file, for loading an index without copying. */
struct spill spill_map_ro(int fd, size_t bytes);

void spill_release(struct spill s);
void spill_unmap(void *p, size_t len);

#endif
