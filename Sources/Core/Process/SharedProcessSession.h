#pragma once

#include "Core/Process/ProcessSession.h"

namespace sscore {

/// 返回进程内共享的 MachProcessSession。
/// 首次调用时自动 attach 到当前进程；失败返回 nullptr。
ProcessSession* SharedProcessSession();

} // namespace sscore
