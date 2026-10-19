#pragma once

#include <cstddef>
#include <cstdint>

namespace sscore {

/// 只读内存访问接口。扫描器、调试器、地址解析器都通过它读取目标进程。
class IMemoryReader {
public:
    virtual ~IMemoryReader() = default;

    virtual bool read(
        uint64_t address,
        void* buffer,
        size_t size,
        size_t* bytesRead = nullptr
    ) = 0;
};

} // namespace sscore
