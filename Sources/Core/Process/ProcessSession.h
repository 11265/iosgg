#pragma once

#include <sys/types.h>

namespace sscore {

class IMemoryReader;
class IMemoryWriter;

/// 进程会话生命周期 + 内存访问入口。
/// 具体 Mach 实现见 MachProcessSession（Darwin Adapter）。
class ProcessSession {
public:
    virtual ~ProcessSession() = default;

    virtual bool attach(pid_t pid) = 0;
    virtual void detach() = 0;

    virtual bool isAttached() const = 0;
    virtual pid_t pid() const = 0;

    virtual IMemoryReader* memoryReader() = 0;
    virtual IMemoryWriter* memoryWriter() = 0;
};

} // namespace sscore
