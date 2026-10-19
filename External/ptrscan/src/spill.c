#define _GNU_SOURCE

#include "spill.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif

int spill_wanted(void)
{
    static int on = -1;

    if (on < 0) {
        const char *env = getenv("PTRSCAN_LOW_MEMORY");

        on = (env && env[0] && env[0] != '0');
    }
    return on;
}

static const char *spill_dir(void)
{
    const char *dir = getenv("PTRSCAN_SPILL_DIR");

    return (dir && dir[0]) ? dir : "/tmp";
}

struct spill spill_alloc(size_t bytes)
{
    struct spill s = { NULL, 0 };

    if (bytes == 0)
        return s;

    if (spill_wanted()) {
        char        path[512];
        const char *dir = spill_dir();
        int         n   = snprintf(path, sizeof(path), "%s/ptrscan-spill-%ld-XXXXXX",
                                   dir, (long)getpid());

        if (n > 0 && (size_t)n < sizeof(path)) {
            int fd = mkstemp(path);

            if (fd >= 0) {
                /* It exists only as long as the mapping does. */
                unlink(path);

                if (ftruncate(fd, (off_t)bytes) == 0) {
                    void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                                   MAP_SHARED, fd, 0);

                    close(fd);
                    if (p != MAP_FAILED) {
                        s.p   = p;
                        s.len = bytes;
                        return s;
                    }
                } else {
                    close(fd);
                }
            }
        }
        /* Fall through: anonymous memory is better than failing the run. */
    }

    {
        void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

        if (p != MAP_FAILED) {
            s.p   = p;
            s.len = bytes;
        }
    }
    return s;
}

struct spill spill_map_ro(int fd, size_t bytes)
{
    struct spill s = { NULL, 0 };

    if (fd < 0 || bytes == 0)
        return s;

    {
        void *p = mmap(NULL, bytes, PROT_READ, MAP_PRIVATE, fd, 0);

        if (p != MAP_FAILED) {
            s.p   = p;
            s.len = bytes;
        }
    }
    return s;
}

void spill_release(struct spill s)
{
    spill_unmap(s.p, s.len);
}

void spill_unmap(void *p, size_t len)
{
    if (p && len)
        munmap(p, len);
}
