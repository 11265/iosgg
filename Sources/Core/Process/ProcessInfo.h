#pragma once

#include <sys/types.h>

#include <string>

namespace sscore {

/// 统一进程信息模型。模块只依赖这个结构，不直接持有 Mach Task Port。
struct ProcessInfo {
    pid_t pid = -1;
    std::string name;
    std::string executablePath;
    uint64_t baseAddress = 0;
};

} // namespace sscore
