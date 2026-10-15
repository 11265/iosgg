#ifndef PTRSCAN_API_H
#define PTRSCAN_API_H

/*
 * The part of ptrscan another program is meant to link against: read a value
 * out of a process, ask what an address is, and walk (or verify) the pointer
 * chains a scan produced.
 *
 * Everything here is plain C. Reading *another* process needs that privilege
 * to belong to the program that links this library: root (a jailbroken or
 * TrollStore device) plus the task_for_pid-allow entitlement codesigned into
 * that program. Reading one's own process needs nothing. A dylib injected into
 * the target needs nothing either -- it is already inside.
 */

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PTRSCAN_CHAIN_MAX 64
#define PTRSCAN_TEXT_MAX  1024

/* ---------------------------------------------------------------- reading */

/*
 * Read up to len bytes of pid at addr. Returns the number of bytes read (short
 * at a hole in the mapping), or -1 with errno set.
 */
ssize_t ptrscan_read(pid_t pid, uint64_t addr, void *buf, size_t len);

/* ------------------------------------------------------- describing memory */

enum ptrscan_verdict {
    PTRSCAN_UNMAPPED = 0,
    PTRSCAN_ANON_WRITABLE,   /* heap or a live buffer: a normal scan target   */
    PTRSCAN_WRITABLE_FILE,   /* writable file mapping: check with read first  */
    PTRSCAN_CACHE_FILE,      /* /Caches/: data nothing points at              */
    PTRSCAN_CODE,            /* executable                                    */
    PTRSCAN_ANON_READONLY,   /* reservation or shared cache                   */
    PTRSCAN_FILE_READONLY,   /* read-only file mapping                        */
};

struct ptrscan_region {
    uint64_t start;
    uint64_t end;
    uint64_t offset;                      /* file offset of the mapping     */
    char     perm[8];                     /* "rw-p" and the like            */
    char     backing[PTRSCAN_TEXT_MAX];   /* "" when anonymous              */
    char     module[PTRSCAN_TEXT_MAX];    /* owning module, "" when none    */
    uint32_t seg_type;                    /* VMA_TYPE_* (vma/vm_area.h)     */
    uint32_t seg_index;
    int      verdict;                     /* enum ptrscan_verdict           */
};

/* Fill out for the region containing addr. 0 on success, -1 when unmapped. */
int ptrscan_region(pid_t pid, uint64_t addr, struct ptrscan_region *out);

const char *ptrscan_verdict_text(int verdict);

/*
 * Base address of a module: its lowest mapping. Chain offsets are relative to
 * it, so this is what a caller needs to use a chain on a new launch.
 */
int ptrscan_module_base(pid_t pid, const char *module, uint64_t *base);

/* ----------------------------------------------------------------- chains */

struct ptrscan_chain {
    char     module[PTRSCAN_TEXT_MAX];   /* what the first offset is relative to */
    char     segment[64];                /* ".data[0]", "" when the line has none */
    uint64_t offs[PTRSCAN_CHAIN_MAX];
    int      n;
    char     text[512];                  /* the chain as the file wrote it */
};

/*
 * Parse one chain line ("0x1c018->0x0->0x58cc"); a trailing comment after '#'
 * is ignored. Returns 0 on success, -1 when the line holds no offsets.
 */
int ptrscan_chain_parse(const char *text, struct ptrscan_chain *out);

/*
 * Walk one chain in a live process: the first offset is resolved against the
 * base of `module`, every following offset is added to the value read at the
 * address before it, and `bytes` are read at the end.
 *
 * Returns 0 when the walk and the final read both succeeded, -1 when a hop or
 * the final read could not be read (errno says why).
 */
int ptrscan_walk_chain(pid_t pid, const char *module,
                       const uint64_t *offs, int n, size_t bytes,
                       uint64_t *end_addr, uint64_t *value);

/* --------------------------------------------------- verifying a whole file */

#define PTRSCAN_TALLY_MAX 16

/* How often a value or an address came up. */
struct ptrscan_tally {
    uint64_t v[PTRSCAN_TALLY_MAX];
    long     n[PTRSCAN_TALLY_MAX];
    int      used;
    long     overflow;
};

struct ptrscan_verify_stats {
    long chains;
    long walked;
    long unreadable;
    long mismatched;
    long addr_hits;
    long value_hits;
    long groups;
    long groups_missing;             /* groups whose module is not mapped */
    struct ptrscan_tally addresses;  /* distinct end addresses            */
    struct ptrscan_tally values;     /* distinct u32 values read          */
};

/* Called for every group header, with base == 0 when the module is missing. */
typedef void (*ptrscan_group_cb)(void *ud, const char *group,
                                 const char *module, uint64_t base);

/*
 * Called once per chain. status is 0 for a chain that walked, -1 when it could
 * not be read at all; the two mismatch flags describe chains that walked but
 * did not end where the caller asked for.
 */
typedef void (*ptrscan_chain_cb)(void *ud, const struct ptrscan_chain *chain,
                                 int status, uint64_t end_addr, uint64_t value,
                                 int addr_mismatch, int value_mismatch);

struct ptrscan_verify_opts {
    uint64_t          expect_addr;   /* 0 = do not check the address          */
    uint64_t          expect_val;    /* 0 = do not check the value            */
    size_t            bytes;         /* bytes to read at the end (default 4)  */
    ptrscan_group_cb  group_cb;      /* optional                              */
    ptrscan_chain_cb  chain_cb;      /* optional                              */
    void             *ud;
};

/*
 * Walk every chain of a text file, the output of `ptrscan scan`. Returns 0
 * when every chain walked and matched, -1 otherwise. `out` may be NULL.
 */
int ptrscan_verify_file(pid_t pid, const char *path,
                        const struct ptrscan_verify_opts *opts,
                        struct ptrscan_verify_stats *out);

/* Format a tally as "0x4b x284  0x50 x3", for the caller to print. */
void ptrscan_tally_text(const struct ptrscan_tally *t, char *buf, size_t len);

#ifdef __cplusplus
}
#endif

#endif
