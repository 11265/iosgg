#pragma once

#include <sys/types.h>

#include <cstdint>
#include <string>
#include <vector>

namespace sscore {

/// 统一地址模型：地址无符号、偏移有符号。
using Address = uint64_t;
using AddressOffset = int64_t;

struct PointerChain {
    Address baseAddress = 0;
    Address targetAddress = 0;
    std::vector<AddressOffset> offsets;

    /// 地址所属进程必须明确；不同进程的相同虚拟地址不是同一个对象。
    pid_t pid = -1;
    std::string moduleName;
};

} // namespace sscore
