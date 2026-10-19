#pragma once

#include <cstdint>

namespace sscore {

/// 统一的内存区域描述。搜索、调试器、指针扫描共用。
struct MemoryRegion {
    uint64_t startAddress = 0;
    uint64_t endAddress = 0;
    uint64_t size = 0;

    bool readable = false;
    bool writable = false;
    bool executable = false;
};

} // namespace sscore
