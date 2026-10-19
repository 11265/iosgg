#import "Modules/Scanner/SignatureScanner.h"
#import "Core/Memory/SSMemoryBridge.h"
#import "Services/LogService.h"

#include <stdlib.h>
#include <string.h>

// 特征码结果上限：和值搜索同量级，避免异常特征码扫出天量命中
#define 最大特征码结果数 (2000000)

// 全局变量
static SignatureSearchCallback signature_search_callback = NULL;

// 添加设置回调函数
void 设置特征码搜索回调(SignatureSearchCallback callback) {
    signature_search_callback = callback;
}

// ── 结果缓冲：匹配算法在 C++ 核心里，这里只负责“收下来” ──────────────
typedef struct {
    uint64_t *items;
    size_t count;
    size_t capacity;
    size_t overflow;
    bool failed;
} 特征码结果;

static void 收集匹配(void *context, uint64_t address) {
    特征码结果 *r = (特征码结果 *)context;
    if (r->failed) return;

    if (r->count >= (size_t)最大特征码结果数) {
        r->overflow++;
        return;
    }

    if (r->count >= r->capacity) {
        size_t new_capacity = r->capacity ? r->capacity * 2 : 1024;
        if (new_capacity > (size_t)最大特征码结果数) new_capacity = (size_t)最大特征码结果数;
        uint64_t *items = (uint64_t *)realloc(r->items, new_capacity * sizeof(uint64_t));
        if (!items) {
            r->failed = true;
            return;
        }
        r->items = items;
        r->capacity = new_capacity;
    }

    r->items[r->count++] = address;
    if (r->count <= 5) {
        [LoggingService log:@"找到匹配: 0x%llx", address];
    }
}

void 搜索模式三(const char* pattern) {
    [LoggingService log:@"执行特征码搜索 - 模式: %s", pattern];

    SearchPattern* search_pattern = 解析特征码(pattern);
    if (!search_pattern) {
        [LoggingService log:@"特征码解析失败"];
        return;
    }

    if (search_pattern->length == 0) {
        [LoggingService log:@"特征码为空，已取消搜索"];
        释放特征码(search_pattern);
        return;
    }

    特征码结果 结果 = {0};
    结果.capacity = 1024;
    结果.items = (uint64_t *)malloc(结果.capacity * sizeof(uint64_t));
    if (!结果.items) {
        释放特征码(search_pattern);
        [LoggingService log:@"无法分配结果缓冲区"];
        return;
    }

    // 通过 Shared Core 枚举区域和读取内存，不再直接调用 mach_vm_*。
    uint64_t cursor = 0;
    SSMemoryRegionInfo region;

    while (SSMemoryNextRegion(&cursor, false, &region)) {
        if (!region.readable) continue;
        if (region.startAddress >= SIGNATURE_SEARCH_RANGE_END) break;
        if (region.endAddress <= SIGNATURE_SEARCH_RANGE_START) continue;

        const uint64_t valid_start = region.startAddress < SIGNATURE_SEARCH_RANGE_START
            ? SIGNATURE_SEARCH_RANGE_START
            : region.startAddress;
        const uint64_t valid_end = region.endAddress > SIGNATURE_SEARCH_RANGE_END
            ? SIGNATURE_SEARCH_RANGE_END
            : region.endAddress;
        if (valid_end <= valid_start) continue;

        const size_t adjusted_size = (size_t)(valid_end - valid_start);
        if (adjusted_size < search_pattern->length) continue;

        void* buffer = malloc(adjusted_size);
        if (!buffer) continue;

        size_t out_size = 0;
        const bool ok = SSMemoryRead(valid_start, buffer, adjusted_size, &out_size);
        if (ok && out_size == adjusted_size) {
            // 纯算法在 C++ 核心里：Sunday 匹配 + 命中回调
            扫描特征码缓冲区(search_pattern, (const uint8_t *)buffer, adjusted_size,
                              valid_start, 收集匹配, &结果);
            if (结果.failed) {
                [LoggingService log:@"无法扩展结果缓冲区，停止本次扫描"];
                free(buffer);
                break;
            }
        }

        free(buffer);
    }

    if (结果.overflow > 0) {
        [LoggingService log:@"特征码搜索完成：命中 %zu 条，保留 %zu 条（超过上限，其余未保留）",
            结果.count + 结果.overflow, 结果.count];
    } else {
        [LoggingService log:@"特征码搜索完成，找到 %zu 个匹配结果", 结果.count];
    }

    // 使用专用回调
    if (结果.count > 0 && signature_search_callback) {
        signature_search_callback(结果.items, 结果.count);
    }

    // 清理资源
    free(结果.items);
    释放特征码(search_pattern);
    [LoggingService log:@"特征码资源已释放"];
}
