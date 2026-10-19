#include "Core/Process/MachProcessSession.h"

#include <mach/mach.h>

#include <unistd.h>

namespace sscore {

MachProcessSession::~MachProcessSession() {
    detach();
}

bool MachProcessSession::attach(pid_t pid) {
    if (_pid == pid && isAttached()) return true;

    detach();

    _pid = pid > 0 ? pid : getpid();

    if (_pid == getpid()) {
        // 典型 tweak 场景：注入在目标进程内部，直接使用自身 task port。
        _task = mach_task_self();
        _ownsTask = false;
    } else {
        mach_port_t task = MACH_PORT_NULL;
        kern_return_t kr = task_for_pid(mach_task_self(), _pid, &task);
        if (kr != KERN_SUCCESS || task == MACH_PORT_NULL) {
            _task = MACH_PORT_NULL;
            _pid = -1;
            return false;
        }
        _task = task;
        _ownsTask = true;
    }

    if (_task == MACH_PORT_NULL) {
        _pid = -1;
        return false;
    }

    _reader = std::make_unique<MachMemoryReader>(_task);
    _writer = std::make_unique<MachMemoryWriter>(_task);
    return true;
}

void MachProcessSession::detach() {
    _reader.reset();
    _writer.reset();

    if (_ownsTask && _task != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), _task);
    }

    _task = MACH_PORT_NULL;
    _ownsTask = false;
    _pid = -1;
}

bool MachProcessSession::isAttached() const {
    return _task != MACH_PORT_NULL && _reader != nullptr;
}

pid_t MachProcessSession::pid() const {
    return _pid;
}

IMemoryReader* MachProcessSession::memoryReader() {
    return _reader.get();
}

IMemoryWriter* MachProcessSession::memoryWriter() {
    return _writer.get();
}

mach_port_t MachProcessSession::taskPort() const {
    return _task;
}

} // namespace sscore
