#pragma once

#include "Core/Memory/MachMemoryReader.h"
#include "Core/Process/ProcessSession.h"

#include <mach/mach.h>

#include <memory>

namespace sscore {

/// Mach/Darwin 的 ProcessSession 实现。
/// 本进程（tweak 注入的游戏）直接使用 mach_task_self()；
/// 跨进程时尝试 task_for_pid，失败则 attach 失败。
class MachProcessSession final : public ProcessSession {
public:
    MachProcessSession() = default;
    ~MachProcessSession() override;

    bool attach(pid_t pid) override;
    void detach() override;

    bool isAttached() const override;
    pid_t pid() const override;

    IMemoryReader* memoryReader() override;
    IMemoryWriter* memoryWriter() override;

    mach_port_t taskPort() const;

private:
    pid_t _pid = -1;
    mach_port_t _task = MACH_PORT_NULL;
    bool _ownsTask = false;
    std::unique_ptr<MachMemoryReader> _reader;
    std::unique_ptr<MachMemoryWriter> _writer;
};

} // namespace sscore
