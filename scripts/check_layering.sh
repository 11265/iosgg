#!/usr/bin/env bash
# 分层约束检查：UI 必须是纯 Objective-C，核心必须是纯 C++17。
set -euo pipefail

cd "$(dirname "$0")/.."

failed=0

report() {
    printf 'LAYERING VIOLATION: %s\n' "$*" >&2
    failed=1
}

# 1. UI 目录不允许 Objective-C++ 文件
ui_mm="$(find Sources/UI -type f -name '*.mm' -print)"
if [[ -n "$ui_mm" ]]; then
    report "Sources/UI 下仍有 .mm 文件：$ui_mm"
fi

# 2. UI 源码不允许出现 C++ 语法/标准库
if grep -RInE 'std::|#include[[:space:]]*<(vector|string|map|unordered_map|memory|algorithm)>|namespace[[:space:]]+[A-Za-z_]|template[[:space:]]*<' \
        Sources/UI --include='*.m' --include='*.h' >/dev/null; then
    report "Sources/UI 的 .m/.h 里出现了 C++ 语法或标准库"
    grep -RInE 'std::|#include[[:space:]]*<(vector|string|map|unordered_map|memory|algorithm)>|namespace[[:space:]]+[A-Za-z_]|template[[:space:]]*<' \
        Sources/UI --include='*.m' --include='*.h' || true
fi

# 3. 核心目录不允许依赖 Foundation / UIKit / ObjC 运行时
if grep -RInE '^[[:space:]]*#import|^[[:space:]]*#include[[:space:]]*[<"](Foundation|UIKit|objc)/|^[[:space:]]*@interface' \
        Sources/Core/Algorithms >/dev/null; then
    report "Sources/Core/Algorithms 里出现了 Objective-C 依赖"
    grep -RInE '^[[:space:]]*#import|^[[:space:]]*#include[[:space:]]*[<"](Foundation|UIKit|objc)/|^[[:space:]]*@interface' \
        Sources/Core/Algorithms || true
fi

# 4. 所有 .cpp 都不允许 import ObjC 头
if grep -RInE '^[[:space:]]*#import' Sources --include='*.cpp' >/dev/null; then
    report "Sources 下的 .cpp 仍在使用 #import"
    grep -RInE '^[[:space:]]*#import' Sources --include='*.cpp' || true
fi

# 5. 核心实现必须存在，防止有人把算法又搬回 ObjC
for expected in \
    Sources/Core/Algorithms/SSScanCore.cpp \
    Sources/Core/Algorithms/SSSignatureCore.cpp \
    Sources/Core/Algorithms/SSPointerChainCore.cpp; do
    if [[ ! -f "$expected" ]]; then
        report "缺少核心实现：$expected"
    fi
done

# 6. 独立编译约束：核心静态库 + UI/tweak 两阶段
if ! grep -q 'LINKAGE_TYPE *= *static' Build/Core/Makefile; then
    report "Build/Core/Makefile 没有把 sscore 声明为 static library"
fi
if ! grep -q 'Sources/Core/Algorithms' Build/Core/Makefile; then
    report "Build/Core/Makefile 没有限定只编译 Sources/Core/Algorithms"
fi
if ! grep -q 'Sources/Core/Algorithms/\*' Tweak.mk; then
    report "Tweak.mk 没有排除 Sources/Core/Algorithms（核心会被重复编译）"
fi
if ! grep -q 'CORE_LIB' Tweak.mk; then
    report "Tweak.mk 没有链接 CORE_LIB"
fi
if ! grep -q 'Build/Core' Makefile; then
    report "顶层 Makefile 没有指向 Build/Core"
fi

# 7. UI 不允许直接依赖 Mach VM API（必须走 Shared Core 的 SSMemoryBridge）
if grep -RInE 'mach_vm_|mach_task_self|vm_protect|vm_region|KERN_SUCCESS|kern_return_t' \
        Sources/UI --include='*.m' --include='*.h' >/dev/null; then
    report "Sources/UI 仍在直接调用 Mach VM API"
    grep -RInE 'mach_vm_|mach_task_self|vm_protect|vm_region|KERN_SUCCESS|kern_return_t' \
        Sources/UI --include='*.m' --include='*.h' || true
fi

# 8. SSDebugger.mm 不允许再 include DynaDbg 实现文件
if grep -nE '^[[:space:]]*#include[[:space:]]+"DynaDbg/.*\.(mm|cpp)"' \
        Sources/Modules/Debugger/SSDebugger.mm >/dev/null; then
    report "SSDebugger.mm 仍在 #include DynaDbg 实现文件"
    grep -nE '^[[:space:]]*#include[[:space:]]+"DynaDbg/.*\.(mm|cpp)"' \
        Sources/Modules/Debugger/SSDebugger.mm || true
fi

# 9. DynaDbg 的关键实现文件必须独立参与编译（清单在 DynaDbg.mk）
dynadbg_mk="Sources/Modules/Debugger/DynaDbg/DynaDbg.mk"
if [[ ! -f "$dynadbg_mk" ]]; then
    report "缺少 DynaDbg 构建清单：$dynadbg_mk"
fi
if ! grep -q 'DynaDbg.mk' Tweak.mk; then
    report "Tweak.mk 没有 include DynaDbg.mk"
fi
for dynadbg in \
    debugger_native_api.mm debugger_core.mm debugger_watchpoint.mm \
    debugger_breakpoint.mm debugger_exception.mm debugger_trace.mm \
    debugger_register.mm debugger_unwind.mm native_api.mm process_api.mm \
    file_api.mm util.cpp trace_file.cpp arm64_decoder.cpp; do
    if ! grep -q "$dynadbg" "$dynadbg_mk"; then
        report "DynaDbg.mk 没有独立编译 DynaDbg/$dynadbg"
    fi
done

# 10. Shared Core 文件必须存在
for core in \
    Sources/Core/Memory/IMemoryReader.h \
    Sources/Core/Memory/IMemoryWriter.h \
    Sources/Core/Memory/MemoryRegion.h \
    Sources/Core/Memory/MachMemoryReader.mm \
    Sources/Core/Memory/SSMemoryBridge.h \
    Sources/Core/Process/ProcessSession.h \
    Sources/Core/Process/MachProcessSession.mm; do
    if [[ ! -f "$core" ]]; then
        report "缺少 Shared Core 文件：$core"
    fi
done

# 11. PtrScan 必须源码 in-process：不链接预编译库，不编译 CLI/public API
ptrscan_mk="External/ptrscan/ptrscan.mk"
if [[ ! -f "$ptrscan_mk" ]]; then
    report "缺少 PtrScan 构建清单：$ptrscan_mk"
fi
if ! grep -q 'ptrscan.mk' Tweak.mk; then
    report "Tweak.mk 没有 include ptrscan.mk"
fi
for mk in Tweak.mk "$ptrscan_mk"; do
    if grep -q 'libptrscan-ios-arm64' "$mk"; then
        report "$mk 仍引用预编译 PtrScan 库"
    fi
    if grep -q 'External/ptrscan/src/main.c' "$mk"; then
        report "$mk 不应编译 PtrScan CLI (main.c)"
    fi
    if grep -q 'External/ptrscan/src/api.c' "$mk"; then
        report "$mk 不应编译 PtrScan public API (api.c)"
    fi
done
for ptrsrc in \
    fs_ptrscan.c ptr_index.c pc_list.c spill.c \
    format/txt.c format/idx.c format/pcf.c \
    vma/vma_map.c vma/vm_area.c vma/vma_select.c vma/image.c vma/image_probe.c \
    platform/mach_common.c platform/maps_apple.c platform/mem_apple.c; do
    if ! grep -q "$ptrsrc" "$ptrscan_mk"; then
        report "ptrscan.mk 没有编译 PtrScan 源码 $ptrsrc"
    fi
done

# 12. 阶段 2：MemoryAnalysis 已拆成 PointerScan + Disassembly
if [[ -d Sources/Modules/MemoryAnalysis ]]; then
    report "Sources/Modules/MemoryAnalysis 仍然存在（应已拆到 PointerScan/Disassembly）"
fi
if grep -RIn 'Modules/MemoryAnalysis' Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.x' >/dev/null; then
    report "仍有代码引用 Modules/MemoryAnalysis"
    grep -RIn 'Modules/MemoryAnalysis' Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.x' || true
fi
for ptrfile in \
    Sources/Modules/PointerScan/PtrScanBridge.h \
    Sources/Modules/PointerScan/PointerScanner.h \
    Sources/Modules/PointerScan/PointerChainParser.h \
    Sources/Modules/PointerScan/SSPointerScanModule.h; do
    if [[ ! -f "$ptrfile" ]]; then
        report "缺少 PointerScan 文件：$ptrfile"
    fi
done
for disfile in \
    Sources/Modules/Disassembly/ARM64Assembler.h \
    Sources/Modules/Disassembly/InstructionBrowser.h \
    Sources/Modules/Disassembly/SSInstructionExplainer.h \
    Sources/Modules/Disassembly/AIAnalysisService.h; do
    if [[ ! -f "$disfile" ]]; then
        report "缺少 Disassembly 文件：$disfile"
    fi
done
if ! grep -q 'Modules/PointerScan/SSPointerScanModule.h' Sources/Tweak.x; then
    report "Tweak.x 没有引用新的 SSPointerScanModule"
fi
if grep -q 'SSMemoryAnalysisModule' Sources/Tweak.x; then
    report "Tweak.x 仍引用旧 SSMemoryAnalysisModule"
fi

# 13. 阶段 3：UI/Pages/System 已拆分到 Access / ProcessInfo / Remote / Shell
if [[ -d Sources/UI/Pages/System ]]; then
    report "Sources/UI/Pages/System 仍然存在（应已拆分）"
fi
if grep -RIn 'UI/Pages/System' Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.x' >/dev/null; then
    report "仍有代码引用 UI/Pages/System"
    grep -RIn 'UI/Pages/System' Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.x' || true
fi
for pagefile in \
    Sources/UI/Pages/Debugger/Access/AccessDetailViewController.h \
    Sources/UI/Pages/Debugger/Access/AccessRegisterViewController.h \
    Sources/UI/Pages/Debugger/BreakpointHitPresenter.h \
    Sources/UI/Pages/ProcessInfo/ModulePage.h \
    Sources/UI/Pages/ProcessInfo/OffsetCalcPage.h \
    Sources/UI/Pages/Remote/RemoteCallPage.h \
    Sources/UI/Pages/Shell/MorePage.h \
    Sources/UI/Pages/Shell/SettingsPage.h; do
    if [[ ! -f "$pagefile" ]]; then
        report "缺少阶段 3 页面：$pagefile"
    fi
done
if ! grep -q 'UI/Pages/Debugger/BreakpointHitPresenter.h' Sources/Tweak.x; then
    report "Tweak.x 没有引用新的 BreakpointHitPresenter 路径"
fi

# 14. 阶段 4：Core 命名与归属
for olddir in Sources/Core/Engine Sources/Core/Module; do
    if [[ -d "$olddir" ]]; then
        report "旧目录仍然存在：$olddir"
    fi
done
for newfile in \
    Sources/Core/Algorithms/SSScanCore.cpp \
    Sources/Core/Algorithms/SSSignatureCore.cpp \
    Sources/Core/Algorithms/SSPointerChainCore.cpp \
    Sources/App/Module/SSModuleManager.h \
    Sources/App/Module/SSModuleProtocol.h; do
    if [[ ! -f "$newfile" ]]; then
        report "缺少阶段 4 文件：$newfile"
    fi
done
if grep -RInE 'Core/(Engine|Module)' Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.cpp' --include='*.x' >/dev/null; then
    report "仍有代码引用旧的 Core/Engine 或 Core/Module"
    grep -RInE 'Core/(Engine|Module)' Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.cpp' --include='*.x' || true
fi
if ! grep -q 'App/Module/SSModuleManager.h' Sources/Tweak.x; then
    report "Tweak.x 没有引用新的 App/Module/SSModuleManager.h"
fi

# 15. 阶段 5：进程/内存原语归 Core，Access 组件/模型归拢
for oldfile in \
    Sources/Modules/ProcessInfo/ProcessMemory.h \
    Sources/Modules/ProcessInfo/TaskPortManager.h \
    Sources/Modules/ProcessInfo/TaskPortManager.m \
    Sources/Models/AccessRecord.h \
    Sources/Models/AccessViewModel.h; do
    if [[ -e "$oldfile" ]]; then
        report "旧文件仍然存在：$oldfile"
    fi
done
for newfile in \
    Sources/Core/Platform/ProcessMemory.h \
    Sources/Core/Process/TaskPortManager.h \
    Sources/Core/Process/TaskPortManager.m \
    Sources/Modules/Debugger/Access/AccessRecord.h \
    Sources/Modules/Debugger/Access/AccessViewModel.h \
    Sources/UI/Pages/Debugger/Access/Components/AccessCell.h \
    Sources/UI/Pages/Debugger/Access/Components/AccessHeaderView.h; do
    if [[ ! -f "$newfile" ]]; then
        report "缺少阶段 5 文件：$newfile"
    fi
done
if grep -RInE 'Modules/ProcessInfo/(ProcessMemory|TaskPortManager)|Models/(AccessRecord|AccessViewModel)|UI/Components/(AccessCell|AccessHeaderView)' \
        Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.x' >/dev/null; then
    report "仍有代码引用阶段 5 的旧路径"
    grep -RInE 'Modules/ProcessInfo/(ProcessMemory|TaskPortManager)|Models/(AccessRecord|AccessViewModel)|UI/Components/(AccessCell|AccessHeaderView)' \
        Sources --include='*.m' --include='*.mm' --include='*.h' --include='*.x' || true
fi

if ((failed)); then
    exit 1
fi

printf 'Layering check passed: UI is Objective-C, core is C++17.\n'
