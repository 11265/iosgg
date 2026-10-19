/*
 * The library-facing API: reading a process, describing an address, and
 * walking the chains a scan produced. The CLI's read/region/verify commands
 * are thin printers on top of this, so both behave identically.
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "ptrscan_api.h"

#include "vma/vm_area.h"
#include "vma/vma_map.h"
#include "platform/plat_proc.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>

/* ---------------------------------------------------------------- reading */

ssize_t ptrscan_read(pid_t pid, uint64_t addr, void *buf, size_t len)
{
    struct iovec local;
    struct iovec remote;

    if (!buf || len == 0) {
        errno = EINVAL;
        return -1;
    }

    local.iov_base  = buf;
    local.iov_len   = len;
    remote.iov_base = (void *)(uintptr_t)addr;
    remote.iov_len  = len;

    return plat_proc_readv(pid, &local, 1, &remote, 1);
}

/* ------------------------------------------------------- describing memory */

/*
 * The map plus the image classification (seg_type / module), which is what
 * makes a region's type and owning module available to callers. The
 * classification reads the images from disk, so it needs no privilege over the
 * target -- important when the caller may not read the process yet.
 */
static int api_load_maps(pid_t pid, struct vm_area **out)
{
    int rc = parse_maps(pid, out);

    if (rc != 0) {
        errno = (rc < 0) ? -rc : rc;
        return -1;
    }

    (void)vma_image(*out, 0, NULL, NULL);
    return 0;
}

static int region_verdict(const struct vm_area *v)
{
    int anon = !v->pathname || v->pathname[0] == '[';

    if (anon && v->perm[1] == 'w') return PTRSCAN_ANON_WRITABLE;
    if (anon)                      return PTRSCAN_ANON_READONLY;
    if (v->perm[1] == 'w' && v->pathname && strstr(v->pathname, "/Caches/"))
        return PTRSCAN_CACHE_FILE;
    if (v->perm[1] == 'w')         return PTRSCAN_WRITABLE_FILE;
    if (v->perm[2] == 'x')         return PTRSCAN_CODE;
    return PTRSCAN_FILE_READONLY;
}

const char *ptrscan_verdict_text(int verdict)
{
    switch (verdict) {
    case PTRSCAN_ANON_WRITABLE:
        return "anonymous writable -- heap or a live buffer, the normal kind "
               "of scan target";
    case PTRSCAN_WRITABLE_FILE:
        return "a writable file mapping -- the program may well write live "
               "data here; check the contents with ptrscan_read() before "
               "trusting the reported backing path, which is often "
               "misattributed for the small submap regions on iOS";
    case PTRSCAN_CACHE_FILE:
        return "a mapping of a cache file -- data nothing references by "
               "pointer, chains almost never lead here";
    case PTRSCAN_CODE:
        return "executable code; a chain to it would be a function pointer, "
               "rarely what a value scan wants";
    case PTRSCAN_ANON_READONLY:
        return "anonymous and not writable -- a reservation or a shared cache "
               "mapping, unlikely to be a chain target";
    case PTRSCAN_FILE_READONLY:
        return "file backed and read-only; a scan target only if the program "
               "really stores a pointer to this address";
    default:
        return "not mapped";
    }
}

static const struct vm_area *region_at(const struct vm_area *head, uint64_t addr)
{
    for (const struct vm_area *v = head; v; v = v->next) {
        if (addr >= v->start && addr < v->end)
            return v;
    }
    return NULL;
}

int ptrscan_region(pid_t pid, uint64_t addr, struct ptrscan_region *out)
{
    if (!out) {
        errno = EINVAL;
        return -1;
    }

    struct vm_area *vma = NULL;

    if (api_load_maps(pid, &vma) != 0)
        return -1;

    const struct vm_area *v = region_at(vma, addr);

    if (!v) {
        free_vm_area(vma);
        errno = EFAULT;
        return -1;
    }

    memset(out, 0, sizeof(*out));
    out->start     = v->start;
    out->end       = v->end;
    out->offset    = (uint64_t)v->offset;
    snprintf(out->perm, sizeof(out->perm), "%s", v->perm);
    if (v->pathname)
        snprintf(out->backing, sizeof(out->backing), "%s", v->pathname);
    if (v->module && v->module->pathname)
        snprintf(out->module, sizeof(out->module), "%s", v->module->pathname);
    out->seg_type  = v->seg_type;
    out->seg_index = v->seg_index;
    out->verdict   = region_verdict(v);

    free_vm_area(vma);
    return 0;
}

int ptrscan_module_base(pid_t pid, const char *module, uint64_t *base)
{
    if (!module || !base) {
        errno = EINVAL;
        return -1;
    }

    struct vm_area *vma = NULL;

    if (api_load_maps(pid, &vma) != 0)
        return -1;

    uint64_t found = 0;

    for (const struct vm_area *v = vma; v; v = v->next) {
        if (!v->pathname || strcmp(v->pathname, module) != 0)
            continue;
        if (found == 0 || v->start < found)
            found = v->start;
    }

    free_vm_area(vma);

    if (found == 0) {
        errno = ENOENT;
        return -1;
    }

    *base = found;
    return 0;
}

/* ----------------------------------------------------------------- chains */

int ptrscan_chain_parse(const char *text, struct ptrscan_chain *out)
{
    if (!text || !out) {
        errno = EINVAL;
        return -1;
    }

    memset(out, 0, sizeof(*out));

    const char *hash = strchr(text, '#');
    size_t      len  = hash ? (size_t)(hash - text) : strlen(text);

    while (len > 0 && (text[len - 1] == ' ' || text[len - 1] == '\t' ||
                       text[len - 1] == '\r' || text[len - 1] == '\n'))
        len--;

    if (len == 0 || len >= sizeof(out->text)) {
        errno = EINVAL;
        return -1;
    }

    memcpy(out->text, text, len);
    out->text[len] = '\0';

    const char *p = out->text;

    while (*p && out->n < PTRSCAN_CHAIN_MAX) {
        while (*p == ' ' || *p == '\t')
            p++;

        char    *end = NULL;
        uint64_t v   = strtoull(p, &end, 16);

        if (end == p)
            break;

        out->offs[out->n++] = v;
        p = end;

        if (p[0] == '-' && p[1] == '>')
            p += 2;
        else
            break;
    }

    if (out->n == 0) {
        errno = EINVAL;
        return -1;
    }
    return 0;
}

int ptrscan_walk_chain(pid_t pid, const char *module,
                       const uint64_t *offs, int n, size_t bytes,
                       uint64_t *end_addr, uint64_t *value)
{
    if (!offs || n <= 0 || !end_addr || !value || bytes == 0 || bytes > 8) {
        errno = EINVAL;
        return -1;
    }

    uint64_t base = 0;

    if (ptrscan_module_base(pid, module, &base) != 0)
        return -1;

    uint64_t addr = base + offs[0];

    for (int i = 1; i < n; i++) {
        uint64_t v = 0;
        ssize_t  got = ptrscan_read(pid, addr, &v, sizeof(v));

        if (got != (ssize_t)sizeof(v)) {
            errno = EFAULT;
            *end_addr = 0;
            return -1;
        }
        addr = v + offs[i];
    }

    uint64_t v = 0;
    ssize_t  got = ptrscan_read(pid, addr, &v, bytes);

    if (got != (ssize_t)bytes) {
        *end_addr = addr;
        errno = EFAULT;
        return -1;
    }

    *end_addr = addr;
    *value    = v;
    return 0;
}

void ptrscan_tally_text(const struct ptrscan_tally *t, char *buf, size_t len)
{
    if (!t || !buf || len == 0)
        return;

    buf[0] = '\0';

    size_t used = 0;

    for (int i = 0; i < t->used; i++) {
        int n = snprintf(buf + used, len - used, "%s0x%llx x%ld",
                         i ? "  " : "", (unsigned long long)t->v[i], t->n[i]);

        if (n < 0 || (size_t)n >= len - used)
            return;
        used += (size_t)n;
    }

    if (t->overflow)
        snprintf(buf + used, len - used, "  (+%ld more)", t->overflow);
}

static void tally_add(struct ptrscan_tally *t, uint64_t v)
{
    for (int i = 0; i < t->used; i++) {
        if (t->v[i] == v) {
            t->n[i]++;
            return;
        }
    }
    if (t->used < PTRSCAN_TALLY_MAX) {
        t->v[t->used] = v;
        t->n[t->used] = 1;
        t->used++;
    } else {
        t->overflow++;
    }
}

/* --------------------------------------------------- verifying a whole file */

int ptrscan_verify_file(pid_t pid, const char *path,
                        const struct ptrscan_verify_opts *opts,
                        struct ptrscan_verify_stats *out)
{
    struct ptrscan_verify_opts defaults;
    struct ptrscan_verify_stats stats;

    if (!path) {
        errno = EINVAL;
        return -1;
    }

    if (!opts) {
        memset(&defaults, 0, sizeof(defaults));
        defaults.bytes = 4;
        opts = &defaults;
    } else if (opts->bytes == 0) {
        defaults    = *opts;
        defaults.bytes = 4;
        opts = &defaults;
    }

    memset(&stats, 0, sizeof(stats));

    FILE *fp = fopen(path, "r");

    if (!fp)
        return -1;

    struct vm_area *vma = NULL;

    if (api_load_maps(pid, &vma) != 0) {
        fclose(fp);
        return -1;
    }

    char     group[PTRSCAN_TEXT_MAX] = "";
    char     module[PTRSCAN_TEXT_MAX] = "";
    uint64_t base      = 0;
    int      have_base = 0;
    char     line[2048];

    while (fgets(line, sizeof(line), fp)) {
        char *hash = strchr(line, '#');

        if (hash)
            *hash = '\0';

        size_t l = strlen(line);

        while (l > 0 && (line[l - 1] == '\n' || line[l - 1] == '\r' ||
                         line[l - 1] == ' '  || line[l - 1] == '\t'))
            line[--l] = '\0';

        if (l == 0)
            continue;

        if (line[0] != ' ' && line[0] != '\t') {
            /* "<module path> .data[0]": the trailing token is the segment. */
            snprintf(group, sizeof(group), "%s", line);

            char *sp = strrchr(group, ' ');

            if (sp && sp[1] == '.') {
                snprintf(module, sizeof(module), "%.*s", (int)(sp - group), group);
                *sp = '\0';
            } else {
                snprintf(module, sizeof(module), "%s", group);
            }

            base      = 0;
            have_base = (ptrscan_module_base(pid, module, &base) == 0);
            stats.groups++;
            if (!have_base) {
                stats.groups_missing++;
                base = 0;
            }

            if (opts->group_cb)
                opts->group_cb(opts->ud, group, module, have_base ? base : 0);
            continue;
        }

        struct ptrscan_chain chain;

        if (ptrscan_chain_parse(line, &chain) != 0)
            continue;

        stats.chains++;

        uint64_t end_addr = 0;
        uint64_t value    = 0;
        int      status   = 0;
        int      addr_mismatch  = 0;
        int      value_mismatch = 0;

        if (!have_base) {
            stats.unreadable++;
            status = -1;
        } else if (ptrscan_walk_chain(pid, module, chain.offs, chain.n,
                                      opts->bytes, &end_addr, &value) != 0) {
            stats.unreadable++;
            status = -1;
        } else {
            if (opts->bytes > 4)
                value &= ~0ULL;   /* keep the wide value as read */

            stats.walked++;
            tally_add(&stats.addresses, end_addr);
            tally_add(&stats.values, value & 0xffffffffULL);

            if (opts->expect_addr) {
                if (end_addr == opts->expect_addr)
                    stats.addr_hits++;
                else {
                    stats.mismatched++;
                    addr_mismatch = 1;
                }
            }
            if (opts->expect_val) {
                if ((value & 0xffffffffULL) == opts->expect_val)
                    stats.value_hits++;
                else {
                    stats.mismatched++;
                    value_mismatch = 1;
                }
            }
        }

        if (opts->chain_cb)
            opts->chain_cb(opts->ud, &chain, status, end_addr, value,
                           addr_mismatch, value_mismatch);
    }

    fclose(fp);
    free_vm_area(vma);

    if (out)
        *out = stats;

    return (stats.unreadable || stats.mismatched || stats.walked == 0) ? -1 : 0;
}
