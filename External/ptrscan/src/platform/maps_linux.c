/*
 * Copyright (C) 2026 kaidev
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
 */

/*
 * Linux / Android memory map backend: /proc/<pid>/maps.
 *
 * Each line has the shape
 *
 *   7f8a2c0000-7f8a2c1000 r-xp 00000000 fd:01 1234  /system/lib64/libc.so
 *
 * which maps one-to-one onto `struct vm_area`: start, end, permissions, file
 * offset, device and inode. Only the file offset matters downstream, because
 * it is what ties a region back to a segment of the on-disk image.
 *
 * The whole file is Linux-only; on Apple platforms the empty translation unit
 * is linked away and maps_apple.c provides the symbols instead.
 */

#include "platform/plat_proc.h"

#if defined(__linux__)

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#include "vma/vm_area.h"

int plat_proc_maps(pid_t pid, struct vm_area **vm_area_out)
{
    if (!vm_area_out)
        return -EINVAL;

    *vm_area_out = NULL;

    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/maps", (int)pid);

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -errno;

    /* Read the entire maps file */
    size_t cap = 64 * 1024;
    size_t len = 0;
    char *buf = malloc(cap);
    if (!buf) {
        close(fd);
        return -ENOMEM;
    }

    for (;;) {
        if (len == cap) {
            size_t new_cap = cap * 2;
            char *tmp = realloc(buf, new_cap);
            if (!tmp) {
                free(buf);
                close(fd);
                return -ENOMEM;
            }
            buf = tmp;
            cap = new_cap;
        }
        ssize_t n = read(fd, buf + len, cap - len);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            int err = -errno;
            free(buf);
            close(fd);
            return err;
        }
        if (n == 0)
            break;
        len += (size_t)n;
    }
    close(fd);

    struct vm_area *head = NULL, *tail = NULL;
    int ret = 0;

    char *p   = buf;
    char *end = buf + len;

    while (p < end) {
        char *nl = memchr(p, '\n', (size_t)(end - p));
        size_t line_len;
        if (nl) {
            line_len = (size_t)(nl - p);
        } else {
            line_len = (size_t)(end - p);
        }

        if (line_len == 0) {
            if (!nl)
                break;
            p = nl + 1;
            continue;
        }

        /* Copy into an independent NUL-terminated string before parsing */
        char *line = malloc(line_len + 1);
        if (!line) {
            ret = -ENOMEM;
            goto cleanup;
        }
        memcpy(line, p, line_len);
        line[line_len] = '\0';

        uint64_t start = 0, end_addr = 0;
        uint64_t offset = 0, inode = 0;
        uint64_t dev_major = 0, dev_minor = 0;
        char perm_str[5] = {0};
        int consumed = 0;

        /*
         * Note: do not put a space before %n, otherwise it will skip the newline.
         * Spaces should only appear between required delimiter fields.
         */
        int matched = sscanf(line,
            "%" SCNx64 "-%" SCNx64 " %4s %" SCNx64
            " %" SCNx64 ":%" SCNx64 " %" SCNu64 "%n",
            &start, &end_addr, perm_str,
            &offset, &dev_major, &dev_minor,
            &inode, &consumed);

        if (matched != 7) {
            free(line);
            if (!nl)
                break;
            p = nl + 1;
            continue;
        }

        size_t pos = ((size_t)consumed <= line_len) ? (size_t)consumed : line_len;

        while (pos < line_len && (line[pos] == ' ' || line[pos] == '\t'))
            pos++;

        char *pathname = NULL;
        if (pos < line_len) {
            size_t path_len = line_len - pos;
            while (path_len > 0 &&
                   (line[pos + path_len - 1] == ' ' ||
                    line[pos + path_len - 1] == '\t')) {
                path_len--;
            }
            if (path_len > 0) {
                pathname = malloc(path_len + 1);
                if (!pathname) {
                    free(line);
                    ret = -ENOMEM;
                    goto cleanup;
                }
                memcpy(pathname, line + pos, path_len);
                pathname[path_len] = '\0';
            }
        }

        free(line);

        struct vm_area *node = calloc(1, sizeof(struct vm_area));
        if (!node) {
            free(pathname);
            ret = -ENOMEM;
            goto cleanup;
        }

        node->start  = start;
        node->end    = end_addr;
        node->offset = (off_t)offset;
        node->dev    = makedev((unsigned)dev_major, (unsigned)dev_minor);
        node->inode  = (ino_t)inode;
        node->pathname = pathname;

        memcpy(node->perm, perm_str, 4);
        node->perm[4] = '\0';

        node->seg_type  = 0;
        node->seg_index = 0;
        node->module    = NULL;
        node->next      = NULL;

        if (!head) head = tail = node;
        else { tail->next = node; tail = node; }

        if (!nl)
            break;
        p = nl + 1;
    }

    free(buf);
    *vm_area_out = head;
    return 0;

cleanup:
    free(buf);
    free_vm_area(head);
    return ret;
}

#endif /* __linux__ */
