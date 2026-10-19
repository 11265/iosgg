#pragma once

#include <cstddef>
#include <cstdint>

namespace sscore {

/// 可写内存访问接口。只有确实需要写内存的模块才依赖它。
class IMemoryWriter {
public:
    virtual ~IMemoryWriter() = default;

    virtual bool write(
        uint64_t address,
        const void* buffer,
        size_t size,
        size_t* bytesWritten = nullptr
    ) = 0;
};

} // namespace sscore
