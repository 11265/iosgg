# iosgg 内存搜索、调试器与 PtrScan 重构实施文档

**项目：** `11265/iosgg`  
**目标：** 建立统一的进程与内存访问基础设施，拆分内存搜索和调试器的编译单元，同时保持 PtrScan 独立二进制运行。  
**技术栈：** Objective-C / Objective-C++ / C++17 / Theos / Mach API / Unix Domain Socket

---

# 1. 重构目标

本次重构不推翻现有项目，而是在保留现有功能的基础上重新划分模块边界。

需要解决以下问题：

1. 内存搜索、调试器存在重复的进程和内存访问逻辑。
2. `SSDebugger.mm` 混合了调试器接口、异常回调和 DynaDbg 实现文件。
3. DynaDbg 部分源码通过 `#include` 直接合并编译，缺少独立编译单元。
4. PtrScan 是独立二进制，不应该被误加入 Tweak 的 `ss_FILES`。
5. 内存搜索、调试器和 PtrScan 需要使用统一的进程信息、地址模型和结果格式。
6. UI 不应该直接依赖 Mach API 或具体扫描算法。

最终实现：

- 内存搜索：独立 C++ 核心。
- 调试器：独立编译单元，继续使用 DynaDbg。
- PtrScan：独立 CLI / IPC 程序。
- Shared Core：统一进程会话、内存访问和地址模型。
- UIKit：保留 Objective-C UI，通过 Bridge 调用底层。

# 2. 最终架构

```text
                         UIKit UI
                            |
             +--------------+--------------+
             |              |              |
         Memory UI      Debugger UI    Pointer UI
             |              |              |
             +--------------+--------------+
                            |
                     Application Layer
                            |
             +--------------+--------------+
             |              |              |
       MemorySearch    DebuggerService  PointerScanClient
             |              |              |
             +--------------+--------------+
                            |
                        Shared Core
                            |
             +--------------+--------------+
             |              |              |
        ProcessSession  MemoryReader   AddressResolver
             |              |              |
             +--------------+--------------+
                            |
                       Darwin Adapter
                            |
                    Mach / VM Operations


     PointerScanClient
             |
       Unix Domain Socket
             |
       PtrScan 独立进程
             |
      Pointer Scanner Engine
             |
      Pointer Index / Analyzer
```

重要原则：

- 搜索算法不直接管理 Mach Task Port。
- 调试器不重复实现进程会话管理。
- PtrScan 不链接进 `ss.dylib`。
- Objective-C UI 不直接访问底层内存。
- 所有模块统一使用进程标识、地址类型和错误码。

# 3. 第一阶段：整理项目目录

建议逐步迁移到以下结构：

```text
iosgg/
├── Makefile
│
├── Sources/
│   ├── Core/
│   │   ├── Process/
│   │   │   ├── ProcessSession.h
│   │   │   ├── ProcessSession.cpp
│   │   │   ├── ProcessInfo.h
│   │   │   └── ProcessManager.cpp
│   │   │
│   │   ├── Memory/
│   │   │   ├── IMemoryReader.h
│   │   │   ├── IMemoryWriter.h
│   │   │   ├── MemoryRegion.h
│   │   │   └── MachMemoryReader.mm
│   │   │
│   │   └── Address/
│   │       ├── AddressResolver.h
│   │       └── AddressResolver.cpp
│   │
│   ├── Modules/
│   │   ├── MemorySearch/
│   │   │   ├── Core/
│   │   │   ├── Algorithms/
│   │   │   ├── Models/
│   │   │   └── Bridge/
│   │   │
│   │   ├── Debugger/
│   │   │   ├── Core/
│   │   │   ├── DynaDbg/
│   │   │   └── Bridge/
│   │   │
│   │   └── PointerScan/
│   │       ├── PointerScanClient.h
│   │       └── PointerScanClient.mm
│   │
│   ├── Services/
│   ├── Models/
│   └── UI/
│
├── External/
│   ├── capstone/
│   ├── keystone/
│   └── ptrscan/
│       ├── include/
│       ├── src/
│       ├── Makefile
│       └── build/
│
└── .github/
    └── workflows/
```

注意：这是一份目标目录结构，不要求第一阶段就移动所有文件。应先建立接口，再逐步迁移实现。

# 4. 第二阶段：建立 Shared Core

这是整个重构最重要的一步。

内存搜索和调试器都需要访问目标进程内存，因此应该统一底层接口。

## 4.1 IMemoryReader

新建：

`Sources/Core/Memory/IMemoryReader.h`

```cpp
#pragma once

#include <cstdint>
#include <cstddef>

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
```

## 4.2 IMemoryWriter

新建：

`Sources/Core/Memory/IMemoryWriter.h`

```cpp
#pragma once

#include <cstdint>
#include <cstddef>

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
```

读写接口分开，避免只需要读取能力的模块被迫依赖写入接口。

## 4.3 ProcessSession

新建：

`Sources/Core/Process/ProcessSession.h`

```cpp
#pragma once

#include <sys/types.h>
#include <memory>

class IMemoryReader;
class IMemoryWriter;

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
```

具体 Mach 实现放在 Darwin Adapter 中。

不要在头文件中暴露不必要的 Mach 内部实现细节。

## 4.4 MemoryRegion

统一内存区域结构：

```cpp
#pragma once

#include <cstdint>

struct MemoryRegion {
    uint64_t startAddress;
    uint64_t endAddress;
    uint64_t size;

    bool readable;
    bool writable;
    bool executable;
};
```

后续内存搜索、指针扫描和调试器都使用统一的区域描述。

## 4.5 重要约束

需要特别注意：

- `ProcessSession` 负责进程会话生命周期。
- `IMemoryReader` 负责读取接口。
- `IMemoryWriter` 负责写入接口。
- `MachMemoryReader` 负责具体 Darwin/Mach 实现。
- 不允许各个模块各自随意创建、释放同一会话的底层资源。

如果调试器需要暂停、恢复、单步执行，应另外建立进程控制接口，由统一的协调器管理状态。

# 5. 第三阶段：重构内存搜索模块

目前已有的关键文件：

```text
ScannerKernel.mm
ScannerState.m
ProcessMemory.m
TaskPortManager.m
PtrScanBridge.mm
PointerScanner.mm
```

建议按照以下方式处理。

## 5.1 ScannerKernel

将纯扫描算法逐步迁移到 C++。

目标：

```text
MemorySearch/
├── Core/
│   ├── ScannerEngine.cpp
│   ├── ScannerKernel.cpp
│   ├── ScannerState.cpp
│   └── ScanResult.cpp
│
├── Algorithms/
│   ├── ExactScanner.cpp
│   ├── UnknownScanner.cpp
│   ├── FuzzyScanner.cpp
│   └── NeonScanner.cpp
│
└── Bridge/
    └── MemorySearchBridge.mm
```

迁移原则：

1. 保留现有 NEON 优化实现。
2. 不要在迁移过程中改变搜索算法。
3. ScannerKernel 通过 IMemoryReader 获取数据。
4. ScannerState 明确状态和资源所有权。
5. UI 只通过 MemorySearchBridge 操作搜索任务。

注意：如果某段代码使用 Foundation、Objective-C Runtime 或 Objective-C 对象，就应该继续使用 `.mm`，不要为了统一扩展名而强制改成 `.cpp`。

## 5.2 ScannerState

重点检查：

- pthread mutex 的创建和销毁。
- atomic 变量的读写规则。
- 搜索任务取消时的状态处理。
- 搜索结果是否存在悬空指针。
- 多线程扫描时是否访问同一块可变状态。

建议将状态定义和扫描算法分离。

## 5.3 ProcessMemory

目前的 `ProcessMemory.m` 更接近兼容性接口，不应直接将其当作真正的内存访问核心。

应逐步统一到：

```text
MachMemoryReader
       |
   IMemoryReader
       |
   ScannerEngine
```

不要保留两套含义相同、实现不同的内存读取接口。

# 6. 第四阶段：拆分 DynaDbg 调试器

当前 `SSDebugger.mm` 的职责过多。

它包含：

- SSDebugger 对外接口。
- DynaDbg 实现文件。
- 异常回调。
- Objective-C 日志和通知。
- C/C++ 之间的接口适配。

需要将实现文件拆成独立编译单元。

## 6.1 删除实现文件的直接 include

在 `SSDebugger.mm` 中删除以下类型的实现文件引用：

```cpp
#include "DynaDbg/debugger/debugger_native_api.mm"
#include "DynaDbg/debugger/debugger_core.mm"
#include "DynaDbg/debugger/debugger_watchpoint.mm"
#include "DynaDbg/debugger/debugger_breakpoint.mm"
#include "DynaDbg/debugger/debugger_exception.mm"
#include "DynaDbg/debugger/debugger_trace.mm"
#include "DynaDbg/debugger/debugger_register.mm"
#include "DynaDbg/debugger/debugger_unwind.mm"

#include "DynaDbg/core/native_api.mm"
#include "DynaDbg/core/process_api.mm"
#include "DynaDbg/core/file_api.mm"

#include "DynaDbg/common/util.cpp"
#include "DynaDbg/common/trace_file.cpp"
#include "DynaDbg/common/arm64_decoder.cpp"
```

这些文件应分别参与编译。

不要同时通过 `#include` 和 Makefile 编译同一个实现文件，否则可能产生重复定义。

## 6.2 DynaDbg 文件职责

建议按以下职责组织：

| 文件 | 主要职责 |
|---|---|
| debugger_core.mm | 调试器核心 |
| debugger_native_api.mm | 原生调试 API |
| debugger_breakpoint.mm | 断点 |
| debugger_watchpoint.mm | 观察点 |
| debugger_exception.mm | 异常处理 |
| debugger_register.mm | 寄存器 |
| debugger_trace.mm | 跟踪 |
| debugger_unwind.mm | 调用栈展开 |
| native_api.mm | 原生接口 |
| process_api.mm | 进程接口 |
| file_api.mm | 文件接口 |
| util.cpp | 通用工具 |
| trace_file.cpp | 跟踪文件 |
| arm64_decoder.cpp | ARM64 解码 |

这些是现有文件的职责划分，不意味着需要重写内部算法。

## 6.3 全局变量和跨文件函数

拆分编译后，原本通过同一翻译单元共享的变量必须有明确的声明和定义。

例如：

```cpp
// debugger_internal.h

#pragma once

class Debugger;

extern Debugger* g_debugger;
```

在唯一一个实现文件中定义：

```cpp
#include "debugger_internal.h"

Debugger* g_debugger = nullptr;
```

注意：实际迁移时必须先搜索当前源码中 `g_debugger` 的真实定义位置，不能直接假设定义就在某个特定文件。

C ABI 函数需要明确声明：

```cpp
#ifdef __cplusplus
extern "C" {
#endif

void native_log(int level, const char* message);

#ifdef __cplusplus
}
#endif
```

同样需要检查异常回调、结构体声明、函数签名以及跨文件静态变量。

## 6.4 不要误加入未确认的源文件

当前 DynaDbg 目录中还有：

```text
core/callback_stubs.mm
core/memory_io.mm
```

它们没有出现在原来的实现文件 include 列表中。

应先检查引用关系、符号定义和调用位置，再决定是否独立编译。

不要因为它们位于 DynaDbg 目录中就自动加入 Makefile。

# 7. 第五阶段：保持 PtrScan 独立二进制

PtrScan 不应该被加入 `ss_FILES`，也不应该把它当作普通的静态库链接。

建议保持两个编译目标：

```text
Theos Target
    |
    +-- ss.dylib
    |
    +-- UIKit
    +-- Shared Core
    +-- MemorySearch
    +-- DynaDbg


PtrScan Target
    |
    +-- ptrscan-ios-arm64
    |
    +-- PointerScanner
    +-- PointerIndex
    +-- PointerAnalyzer
    +-- CLI
    +-- IPC Server
```

## 7.1 PtrScan 与主程序的关系

建议 PtrScan 同时支持两种使用方式：

- CLI：独立终端执行。
- IPC：接受主程序发送的扫描任务。

主程序只需要维护：

```text
PointerScanClient
```

不需要把 PtrScan 的内部扫描算法暴露给 UIKit。

## 7.2 IPC 协议

建议第一版采用 Unix Domain Socket。

协议需要有统一的消息头：

```cpp
struct IPCHeader {
    uint32_t magic;
    uint16_t version;
    uint16_t command;
    uint32_t requestID;
    uint32_t payloadSize;
};
```

实际传输时应使用明确的字节序和长度校验，不能直接把 C++ 结构体内存布局当作稳定网络协议。

第一版至少定义以下命令：

```text
PING
GET_VERSION
START_INDEX
START_SCAN
ANALYZE
GET_TASK_STATUS
CANCEL_TASK
GET_RESULT
SHUTDOWN
```

任务返回统一使用：

```text
requestID
status
errorCode
payload
```

大量扫描结果不要使用 JSON 逐条传输。可以采用二进制批量传输或结果文件。

## 7.3 两种内存访问模式

**模式 A：PtrScan 自己访问目标进程**

PtrScan 自己建立进程会话和内存读取能力。

优点是扫描数据不需要经过 IPC 来回传输。

**模式 B：MemoryBroker 代理读取**

PtrScan 通过 IPC 请求主程序读取内存。

优点是权限和资源管理更加集中，缺点是大量小块读取可能产生较高通信开销。

建议优先采用模式 A，保留模式 B 作为后续扩展。

注意：Mach Port 不能仅通过传递一个 `mach_port_t` 整数值就跨进程共享。需要正确传递 Mach Port Right，或者由 PtrScan 自己取得目标进程访问权限。

## 7.4 PtrScan 的 Makefile

PtrScan 应有自己的 Makefile。

示意：

```makefile
CXX = clang++

CXXFLAGS = -std=c++17 -O2

TARGET = build/ptrscan-ios-arm64

SOURCES = \
    src/main.cpp \
    src/PointerScanner.cpp \
    src/PointerIndex.cpp \
    src/PointerAnalyzer.cpp

all:
	mkdir -p build
	$(CXX) $(CXXFLAGS) $(SOURCES) -o $(TARGET)

clean:
	rm -rf build
```

这只是结构示例。实际应以现有 PtrScan 源码为准，保留其原来的编译参数、平台宏、链接依赖和 Mach API 配置。

# 8. 第六阶段：修改 Theos Makefile

当前 Makefile 中存在：

```makefile
ss_LDFLAGS = External/libcapstone.a \
             External/libkeystone.a \
             External/ptrscan/libptrscan-ios-arm64.a
```

如果 PtrScan 已确定为独立二进制，应移除 PtrScan 静态库链接项。

Capstone 和 Keystone 是否继续链接，应根据 DynaDbg、解码和汇编模块的真实符号引用决定。

## 8.1 DynaDbg 独立编译单元

原来通过 include 编译的文件需要明确加入 `ss_FILES`。

示例：

```makefile
DYNADBG_DIR = Sources/Modules/Debugger/DynaDbg

ss_FILES += \
    $(DYNADBG_DIR)/debugger/debugger_native_api.mm \
    $(DYNADBG_DIR)/debugger/debugger_core.mm \
    $(DYNADBG_DIR)/debugger/debugger_watchpoint.mm \
    $(DYNADBG_DIR)/debugger/debugger_breakpoint.mm \
    $(DYNADBG_DIR)/debugger/debugger_exception.mm \
    $(DYNADBG_DIR)/debugger/debugger_trace.mm \
    $(DYNADBG_DIR)/debugger/debugger_register.mm \
    $(DYNADBG_DIR)/debugger/debugger_unwind.mm \
    $(DYNADBG_DIR)/core/native_api.mm \
    $(DYNADBG_DIR)/core/process_api.mm \
    $(DYNADBG_DIR)/core/file_api.mm \
    $(DYNADBG_DIR)/common/util.cpp \
    $(DYNADBG_DIR)/common/trace_file.cpp \
    $(DYNADBG_DIR)/common/arm64_decoder.cpp
```

需要保留原有 `exception_queue.mm` 的编译方式，避免重复编译。

## 8.2 源文件自动发现

自动发现普通模块源码时，应排除 DynaDbg 目录，避免重复：

```makefile
ss_FILES = $(shell find Sources -type f \( \
    -name '*.m' -o \
    -name '*.mm' -o \
    -name '*.x' -o \
    -name '*.c' -o \
    -name '*.cpp' \
\) ! -path 'Sources/Modules/Debugger/DynaDbg/*')
```

随后再显式加入 DynaDbg 源文件。

注意：最终 Makefile 应结合当前仓库的实际路径、原有源文件列表和 Theos 规则合并，不要直接用示例覆盖整个 Makefile。

# 9. 第七阶段：统一地址模型

内存搜索、调试器和 PtrScan 必须使用统一的地址表示。

建议：

```cpp
using Address = uint64_t;

struct PointerChain {
    Address baseAddress;
    Address targetAddress;

    std::vector<int64_t> offsets;
};
```

统一约定：

- 地址使用无符号 64 位整数。
- 偏移使用有符号 64 位整数。
- 模块基址与绝对地址区分。
- 地址所属进程必须明确。
- 指针链必须保留目标 PID 和模块信息。
- 不要把不同进程的相同虚拟地址视为同一对象。

还需要区分：

1. 当前运行时虚拟地址。
2. 模块加载基址。
3. 模块内偏移。
4. 指针链中的有符号偏移。

这样内存搜索得到的地址才能被调试器观察，也能作为 PtrScan 的目标地址。

# 10. 第八阶段：进程状态协调

这是最容易出现隐蔽问题的地方。

内存搜索可能正在扫描，调试器可能正在暂停或单步执行。

不能让多个模块各自控制同一目标进程的暂停和恢复状态。

建议引入：

```text
ProcessControlCoordinator
```

负责统一管理：

- Attach / Detach。
- Suspend / Resume。
- 单步状态。
- 当前调试状态。
- 内存操作协调。
- 进程退出和会话失效。

基本规则：

1. 搜索任务不能擅自恢复调试器暂停的进程。
2. 调试器单步执行期间，搜索模块应根据会话策略暂停或延迟任务。
3. 进程退出后，所有模块收到会话失效通知。
4. Detach 时统一释放对应资源。
5. 不允许多个模块重复释放同一底层资源。

# 11. 第九阶段：编译与验证

不要一次性完成全部迁移。

每完成一个阶段就编译验证一次。

## 阶段 A：基线验证

- [ ] 拉取当前 main 分支。
- [ ] 记录当前提交 SHA。
- [ ] 确认现有项目可以正常编译。
- [ ] 保存当前可用的 deb。
- [ ] 记录现有内存搜索功能表现。
- [ ] 记录现有 DynaDbg 功能表现。
- [ ] 记录 PtrScan 独立二进制的运行表现。

## 阶段 B：Shared Core

- [ ] 新增 IMemoryReader。
- [ ] 新增 IMemoryWriter。
- [ ] 新增 ProcessSession。
- [ ] 新增 MemoryRegion。
- [ ] 实现 Darwin/Mach Adapter。
- [ ] 检查资源生命周期。
- [ ] 编译测试。

## 阶段 C：内存搜索

- [ ] 拆分 ScannerKernel。
- [ ] 保留 NEON 实现。
- [ ] 整理 ScannerState。
- [ ] 统一内存读取接口。
- [ ] 验证精确搜索。
- [ ] 验证未知初始值搜索。
- [ ] 验证增量搜索。
- [ ] 验证搜索结果稳定性。

## 阶段 D：DynaDbg

- [ ] 删除实现文件的直接 include。
- [ ] 检查全局变量定义。
- [ ] 检查 C/C++ ABI。
- [ ] 检查头文件声明。
- [ ] 修改 ss_FILES。
- [ ] 检查重复符号。
- [ ] 编译测试。
- [ ] 验证断点、寄存器和异常处理。

## 阶段 E：PtrScan

- [ ] 保持独立二进制。
- [ ] 移除主项目对 PtrScan 静态库的错误依赖。
- [ ] 保留 CLI 功能。
- [ ] 实现 IPC Server。
- [ ] 实现 PointerScanClient。
- [ ] 定义协议版本。
- [ ] 验证 index。
- [ ] 验证 scan。
- [ ] 验证 analyze。
- [ ] 验证任务取消和进程退出。

## 阶段 F：整体验证

- [ ] 三个模块可以同时存在。
- [ ] 内存搜索与调试器共享会话。
- [ ] PtrScan 可以独立运行。
- [ ] PtrScan 可以被主程序调用。
- [ ] 地址格式一致。
- [ ] 进程退出后资源正确释放。
- [ ] UI 不直接依赖底层 Mach API。

# 12. 第十阶段：Git 提交规划

建议使用分阶段提交，避免一个巨大提交难以定位问题。

| 提交 | 内容 |
|---|---|
| commit 1 | refactor(core): introduce process and memory interfaces |
| commit 2 | refactor(scanner): separate memory search engine |
| commit 3 | refactor(debugger): split DynaDbg translation units |
| commit 4 | refactor(ptrscan): introduce IPC client and server |
| commit 5 | refactor(address): unify address and pointer chain models |
| commit 6 | test(build): verify integrated modules |

每次提交前：

```bash
git status
git diff --check
git diff
```

编译通过后再提交：

```bash
git add Sources Makefile
git commit -m "refactor(core): introduce process and memory interfaces"
```

PtrScan 如果作为独立子目录或独立构建项目，应根据实际修改内容单独提交。

最终推送：

```bash
git push origin <feature-branch>
```

建议不要直接在 main 上进行大规模重构。

推荐创建：

```bash
git switch -c refactor/memory-debugger-pointer
```

完成全部阶段并验证后，再合并到 main。

# 13. 验收标准

重构完成后，必须达到以下要求：

| 项目 | 验收要求 |
|---|---|
| 内存搜索 | 独立编译，保留现有搜索功能和 NEON 优化 |
| 调试器 | DynaDbg 独立编译单元，不再通过实现文件 include |
| PtrScan | 保持独立二进制，CLI 功能不丢失 |
| Shared Core | 统一进程会话和内存访问接口 |
| 地址模型 | 三个模块使用一致的地址和偏移表示 |
| IPC | 主程序可以启动、控制和获取 PtrScan 结果 |
| UI | 不直接依赖 Mach API |
| 编译 | Theos 和 PtrScan 各自独立构建成功 |
| 兼容性 | 不破坏原有功能 |

# 14. 实施优先级

建议按照下面的顺序执行：

**P0：先完成基础设施**

1. 统一 ProcessSession。
2. 统一 IMemoryReader。
3. 统一 MemoryRegion。
4. 明确进程资源所有权。

**P1：拆分现有代码**

1. 重构 ScannerKernel。
2. 整理 ScannerState。
3. 拆分 SSDebugger。
4. 将 DynaDbg 改为独立编译单元。

**P2：接入独立 PtrScan**

1. 保留独立二进制。
2. 实现 IPC 协议。
3. 实现 PointerScanClient。
4. 统一扫描结果格式。

**P3：整合与优化**

1. 地址解析统一。
2. 进程控制协调。
3. 并发与资源管理。
4. 编译自动化和回归测试。

---

## 最终设计原则

本项目不采用将所有代码合并成一个大型 C++ 模块的方式。

正确的设计是：

- C++ 负责核心算法和业务逻辑。
- Objective-C++ 负责 iOS 系统 API 适配。
- Objective-C 负责现有 UIKit 和 UI 层。
- DynaDbg 作为独立编译单元参与 Tweak 构建。
- PtrScan 保持独立二进制，通过 IPC 与主程序协作。
- Shared Core 统一进程会话、内存接口和地址模型。

这样既能保留现有代码资产，又能让内存搜索、调试器和指针扫描器分别演进。
---

## 实施进度（当前分支）

> 以下是本次实际落地的内容；文档中的 P2/P3 仍按原顺序待做。

### 已完成

- **P0 Shared Core**
  - `Sources/Core/Memory/IMemoryReader.h`、`IMemoryWriter.h`、`MemoryRegion.h`
  - `Sources/Core/Process/ProcessSession.h`、`ProcessInfo.h`
  - `Sources/Core/Address/Address.h`（统一 Address / AddressOffset / PointerChain）
  - `MachMemoryReader.mm`、`MachProcessSession.mm`（Darwin Adapter）
  - `SSMemoryBridge.h/.mm`（C ABI，供 ObjC 模块使用）
- **P1 内存搜索**
  - `Scanner.mm`、`SignatureScanner.m`、`PointerChainParser.m` 已改为通过 Shared Core 读取内存和枚举区域；
  - 保留 NEON 扫描内核与原有搜索/快照/结果文件逻辑。
- **P1 DynaDbg**
  - `SSDebugger.mm` 已删除对 14 个 DynaDbg 实现文件的 `#include`；
  - `Tweak.mk` 显式列出这些文件，全部作为独立编译单元编译；
  - `native_api.h` 补齐 `debugger_new`、观察点/断点/寄存器等 C ABI 声明；
  - 未加入 `callback_stubs.mm`、`memory_io.mm`（按文档要求先确认引用关系）。
- **P1 UI**
  - `Sources/UI` 下已无 `mach_vm_*`、`mach_task_self`、`vm_region_*`、`KERN_SUCCESS` 等直接调用；
  - 读/写/保护/区域查询统一走 `SSMemoryBridge`。
- **构建**
  - C++17 核心仍独立编译为 `build/libsscore.a`；
  - `make`、`make -f Tweak.mk`、`make package FINALPACKAGE=1` 均可用；
  - `scripts/check_layering.sh` 已增加 Shared Core、DynaDbg 独立单元、UI 无 Mach VM 的检查。

### 验证

```bash
./Tests/run_tests.sh
./scripts/check_layering.sh
make clean
make package FINALPACKAGE=1
```


### P2 实施说明（按用户要求：主程序调用，无 CLI）

- `External/ptrscan/src` 下的 fast_ptrscan 源码直接编译进 `ss.dylib`；
- 不再链接 `External/ptrscan/libptrscan-ios-arm64.a`，也不构建 CLI；
- 不做独立进程/IPC；主程序通过 `PtrScanBridge` / `PointerScanner` 调用；
- 只编译 portable core + Apple platform 后端，排除 `main.c`、`api.c` 和 Linux 后端。

### 待完成

- **独立 CLI/IPC（按用户要求不做）**：PtrScan 已改为源码 in-process 集成，不构建 CLI，也不拆独立进程；
- **P3 ProcessControlCoordinator**：尚未引入统一的暂停/恢复/单步状态协调器；
- **地址模型全量迁移**：新模型已建立，但旧模块仍大量使用裸 `uint64_t`；
- **真机回归**：编译已通过，搜索/观察点/断点/PtrScan 的实机行为仍需按文档第 11 节验证。

### 阶段 1 整理（已完成）

- 删除无引用文件：`MemoryProcessor.*`、ObjC `MemoryRegion.*`、`ScanResult.*`、空 `ProcessMemory.m`；
- 新增 `Sources/Modules/Debugger/DynaDbg/DynaDbg.mk`，DynaDbg 源清单从 `Tweak.mk` 移出；
- 新增 `External/ptrscan/ptrscan.mk`，PtrScan 源清单从 `Tweak.mk` 移出；
- 根目录 `Core/` 构建工程迁移到 `Build/Core/`，`Makefile` 与静态库路径同步更新；
- 每一步均通过 `make clean && make package FINALPACKAGE=1` 验证。

### 阶段 2 整理（已完成）

- `Sources/Modules/MemoryAnalysis` 已拆分为：
  - `Modules/PointerScan`：PtrScanBridge、PointerScanner、PointerChainParser、SSPointerScanModule；
  - `Modules/Disassembly`：ARM64Assembler、InstructionBrowser、SSInstructionExplainer、AIAnalysisService。
- `SSMemoryAnalysisModule` 改名为 `SSPointerScanModule`，moduleId 改为 `pointer_scan`，菜单显示名改为「指针扫描」。
- `Tweak.x` 的模块注册、UI 的 import 全部更新到新路径。
- 已删除空的 `Modules/MemoryAnalysis` 目录，不再保留旧路径转发头。
- 每一步均通过 `make clean && make package FINALPACKAGE=1` 验证（串行构建，避免 Theos `.x` 并行缓存竞态）。

### 阶段 3 整理（已完成）

- `Sources/UI/Pages/System` 已拆分并删除：
  - `UI/Pages/Debugger/Access/`：AccessDetailViewController、AccessRegisterViewController；
  - `UI/Pages/Debugger/`：BreakpointHitPresenter；
  - `UI/Pages/ProcessInfo/`：ModulePage、OffsetCalcPage；
  - `UI/Pages/Remote/`：RemoteCallPage；
  - `UI/Pages/Shell/`：MorePage、SettingsPage。
- `Tweak.x`、`SSProcessInfoModule`、`SSRemoteModule` 以及页面内部的 import 全部更新到新路径。
- 空的 `UI/Pages/System` 目录已删除，不再保留转发头。
- 每一步均通过 `make clean && make package FINALPACKAGE=1` 验证（串行构建）。

### 阶段 4 整理（已完成）

- `Sources/Core/Engine` → `Sources/Core/Algorithms`：
  - SSScanCore.cpp、SSSignatureCore.cpp、SSPointerChainCore.cpp/.h；
  - `Build/Core/Makefile`、`Tests/run_tests.sh`、`Tests/CoreEngineTests.cpp`、`Tweak.mk`、`scripts/check_layering.sh` 路径全部同步。
- `Sources/Core/Module` → `Sources/App/Module`：
  - SSModuleManager.h/.m、SSModuleProtocol.h；
  - `Tweak.x`、MorePage、各功能模块头文件的 import 全部更新。
- 旧 `Core/Engine`、`Core/Module` 目录已删除，无转发头。
- 每一步均通过 `make clean && make package FINALPACKAGE=1` 验证（串行构建）。

### 阶段 5 整理（已完成）

- `Modules/ProcessInfo/ProcessMemory.h` → `Core/Platform/ProcessMemory.h`；
- `Modules/ProcessInfo/TaskPortManager.h/.m` → `Core/Process/TaskPortManager.h/.m`；
- 相关 import 已更新：RemoteCallEngine、SunScanner、InstructionBrowser、SSProcessInfoModule、MachMemoryReader、SSMemoryBridge 等。
- Access 组件/模型归拢：
  - `Models/AccessRecord.*`、`Models/AccessViewModel.*` → `Modules/Debugger/Access/`；
  - `UI/Components/AccessCell.*`、`AccessHeaderView.*` → `UI/Pages/Debugger/Access/Components/`；
  - AccessPage、AccessDetail、AccessHitInspector、RecordPage 等 import 已更新。
- 每一步均通过 `make clean && make package FINALPACKAGE=1` 验证（串行构建）。
