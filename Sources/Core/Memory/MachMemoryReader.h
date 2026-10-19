#pragma once

#include "Core/Memory/IMemoryReader.h"
#include "Core/Memory/IMemoryWriter.h"

#include <mach/mach.h>

namespace sscore {

/// Darwin/Mach 适配器：只负责把 Mach API 包成 IMemoryReader / IMemoryWriter。
class MachMemoryReader final : public IMemoryReader {
public:
    explicit MachMemoryReader(mach_port_t task);

    bool read(uint64_t address, void* buffer, size_t size, size_t* bytesRead = nullptr) override;

private:
    mach_port_t _task = MACH_PORT_NULL;
};

class MachMemoryWriter final : public IMemoryWriter {
public:
    explicit MachMemoryWriter(mach_port_t task);

    bool write(uint64_t address, const void* buffer, size_t size, size_t* bytesWritten = nullptr) override;

private:
    mach_port_t _task = MACH_PORT_NULL;
};

} // namespace sscore
