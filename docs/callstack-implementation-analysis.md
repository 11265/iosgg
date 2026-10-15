# 调试器「堆栈调用数据」（调用栈 / backtrace）实现分析

> 结论一句话：**消费端（UI / 数据模型）已经全部接好，生产端（真正抓取调用栈的代码）完全缺失**——
> `userInfo[@"callStack"]` 从来没有人写入，所以详情页的"调用栈"永远为空。
> 实现路径是在 Mach 异常处理线程内，用**出错线程冻结状态下的 fp/lr/sp/pc 做 FP 链回溯**，并把结果同步塞进通知。

---

## 0. 实现状态（P0 已实现）

| 内容 | 位置 |
| --- | --- |
| ARM64 FP 链展开（无分配、无锁、带全部合法性校验） | `Sources/Services/Debugger/DynaDbg/debugger/debugger_unwind.mm` |
| 接口声明 | `Sources/Services/Debugger/DynaDbg/core/native_api.h`（"Call stack unwinding" 段） |
| 异常窗口内同步抓取 + 通知 `callStack` + `lastCallStack` | `Sources/Services/Debugger/SSDebugger.mm`（`send_exception_info`） |
| 按需抓取接口 | `SSDebugger.h/.mm` 的 `captureCallStackForThread:` |
| 算法级回归测试（g++ + 桩，无需设备） | `tests/unwind_fp_chain_test.py` |

验证结果：

- 算法：`python3 tests/unwind_fp_chain_test.py` —— 17 项断言全部通过（`-Wall -Wextra` 无警告）；
- 构建：WSL + theos + `iPhoneOS16.5.sdk` 交叉工具链 `make` 通过（arm64，0 error / 0 warning，产出 `ss.dylib`）。
  踩到并修掉一个真实问题：`lastCallStack` 的 `readwrite` 重声明所在的 class extension 原本在
  `send_exception_info` 之后，编译期仍按 `readonly` 处理，报 `assignment to readonly property`，
  已把 extension 上移到所有赋值点之前；

构建方式说明：`DynaDbg/debugger/*.mm` 是**被 `SSDebugger.mm` `#include` 进同一个编译单元**的，
新文件只需加 `#include`，**不要**登记到 `ss_FILES`，否则符号重复定义。

实现注意：把 `lastCallStack` 改成 `readwrite` 的 class extension 必须出现在**所有赋值点之前**。
`send_exception_info()` 定义在文件前部，因此 extension 已上移到 `#import` 之后；
否则编译期仍按头文件的 `readonly` 处理（`assignment to readonly property`）。

---

## 1. 现状：数据链路与缺口

| 环节 | 位置 | 状态 |
| --- | --- | --- |
| 异常寄存器快照（含 fp/lr/sp/pc） | `Sources/Services/Debugger/DynaDbg/debugger/debugger_exception.mm:68-79` | 已有 |
| 原生 → ObjC 回调入口 | `Sources/Services/Debugger/SSDebugger.mm:35` `send_exception_info()` | 已有 |
| 组装通知 userInfo | `Sources/Services/Debugger/SSDebugger.mm` 的 `send_exception_info` | 原先缺 `callStack` key，P0 已补齐 |

| 调试器对外属性 | `Sources/Services/Debugger/SSDebugger.h:18` `lastCallStack` | 原先只声明、无人赋值；P0 已在 class extension 中改为 `readwrite` 并写入 |

| 模型字段 | `Sources/Models/AccessRecord.h:16,28` | 已有 |
| 视图模型读取 | `Sources/Models/AccessViewModel.m:251` → `:261` → `:299` → `:322/338/353` | 已有 |
| 详情页透传 | `Sources/UI/Pages/AccessDetailViewController.m:159-163` | 已有 |
| 界面渲染（hex 字符串 → frame 列表） | `Sources/UI/Pages/AccessRegisterViewController.m:198-213` | 已有 |

全仓库搜索 `callStack` 只有 17 处，全部是"读取方"，**没有任何写入方**。
即：现在 `hit.callStack` 恒为 `nil`，`AccessRegisterViewController` 的调用栈分区永远空着。

---

## 2. 数据契约（保持与现有 UI 兼容）

现有 UI 已固定按下面格式解析（`AccessRegisterViewController.m:199-211`）：

```objc
self.callStack[i]  // NSString，形如 @"0x104a3c1f0"
uint64_t addr = strtoull([addrStr UTF8String], NULL, 16);
```

因此生产端必须产出：

- 类型：`NSArray<NSString *>`，元素 `[NSString stringWithFormat:@"0x%llX", addr]`
- `frame[0]` = **触发指令 PC**（异常发生处），后续为各级返回地址（越靠后越外层）
- 建议附带 `threadId`（`debugger_exception.mm:79` 已有 `info->thread_id`）
- 帧数上限 64（防止野指针链把数组撑爆）
- 若将来要带符号名，**新增 key（如 `callStackFrames`）**，不要改变 `callStack` 的 `NSString` 语义，否则要同时改 `AccessViewModel` + `AccessRegisterViewController`

---

## 3. 采集时机与线程模型（决定代码写在哪）

事实（均可在源码中核对）：

1. 调试器注册的是**自身进程**的异常端口：`SSDebugger.mm:22` `pid = getpid()`；`debugger_core.mm:271-284` 由此走 `mach_task_self()` 内嵌模式。
2. 异常端口为 `EXC_MASK_BREAKPOINT | EXC_MASK_GUARD`，行为 `EXCEPTION_DEFAULT`（`debugger_core.mm:304`）。
3. 消息循环跑在**独立线程**上：`debugger_native_api.mm:41` 起 `std::thread(... run())`，`debugger_core.mm:321-334` 用 `mach_msg_server(exc_server, ...)`。
4. 异常消息投递后，**出错线程在内核里等待 handler 的 reply，寄存器与栈是冻结的**——这是唯一可靠的快照窗口。
5. 进入 break state 时会显式 `thread_suspend(thread)`（`debugger_exception.mm:411 / 911 / 969`），并把冻结的寄存器存进 `thread_states_`（`debugger_types.h:93-104`）。
6. 但"自动继续 / 跟踪写文件"分支（`should_notify == false`、trace 模式）在 handler 返回后**立刻恢复线程**。

推论：

- **必须在 `send_exception_info()` 里、`dispatch_async`（`SSDebugger.mm:84`）之前同步抓完**。
  放到 main queue 的 block 里再去读栈就晚了——那时线程早已恢复，栈内容已经变了。
- 抓取结果同时写入两处：`SSDebugger.lastCallStack`（给按需读取）和 `userInfo[@"callStack"]`（给现有通知链路）。
- 绝不能在异常线程里 `dispatch_sync` 到主队列：**命中的线程很可能就是主线程**（`thread_suspend` 之后主线程根本不会执行任何 ObjC/UI 代码），会直接死锁。现有代码用 `dispatch_async` 是正确的，实现时不要改成同步。
- 顺带说明一个既有设计事实：若被监视地址由主线程访问，进入 break state 后 UI 线程被挂起，界面在 `continue_execution` 之前无法响应。所以调用栈必须是"异常线程内自给自足"的，不能依赖后续由 UI 触发的采集。

---

## 4. 展开算法

### 4.1 P0：FP（frame pointer）链回溯 —— 首选首版方案

ARM64 栈帧约定（AAPCS64 / Apple 一致）：

```
函数入口： stp x29, x30, [sp, #-16]!   ; 保存 caller 的 fp 和返回地址
           mov x29, sp                 ; x29 指向本函数的 frame record
frame record:  [x29]     = caller 的 x29
               [x29 + 8] = 返回地址（回到 caller 的地址）
```

回溯伪代码：

```cpp
// 出错线程的寄存器：pc = 触发指令，fp = x29，sp = 当前栈指针
int unwind_fp_chain(mach_port_t task, uint64_t pc, uint64_t fp, uint64_t sp,
                    uint64_t *out, int max_frames)
{
    if (max_frames <= 0) return 0;
    int n = 0;
    out[n++] = strip_pac(pc);                 // frame 0：出错指令本身

    uint64_t stack_lo = 0, stack_hi = 0;
    if (!stack_region_of(task, sp, &stack_lo, &stack_hi)) return n;  // 拿不到栈区域就不硬走

    uint64_t cur = fp;
    while (n < max_frames) {
        if (cur == 0 || (cur & 0xF) != 0) break;          // 必须 16 字节对齐
        if (cur < sp) break;                              // 不能低于当前 sp
        if (cur < stack_lo || cur + 16 > stack_hi) break; // 必须落在栈区域内

        uint64_t pair[2] = {0, 0};
        mach_vm_size_t got = 0;
        kern_return_t kr = mach_vm_read_overwrite(task, cur, 16,
                                                  (mach_vm_address_t)pair, &got);
        if (kr != KERN_SUCCESS || got != 16) break;

        uint64_t next_fp = strip_pac(pair[0]);
        uint64_t lr      = strip_pac(pair[1]);            // 注意：取自栈，不是当前 x30
        if (lr == 0) break;
        if (!is_executable_addr(task, lr)) break;         // 返回地址必须落在 __TEXT

        out[n++] = lr;
        if (next_fp <= cur) break;                        // 严格递增，防死循环
        cur = next_fp;
    }
    return n;
}
```

关键点与坑：

- **frame 1 必须取 `[fp+8]`，不能用寄存器 x30。** 异常发生在函数中部时 x30 往往被临时占用/已失效；只有 frame record 里的保存值才是权威的。
- **叶子函数例外**：未建立 frame record 的叶子函数里 x29 还指向调用者的 record，直接读 `[fp+8]` 会**跳掉一层调用者**。正确处理是"叶子帧用 LR、非叶子帧用 [fp+8]"，判定优先靠 Compact Unwind 的 frameless 编码（见 4.2），退化方案是查最近符号起点的前两条指令是否为 `stp x29,x30,[sp,#-imm]!` + `mov x29,sp`（可用已链接的 capstone 判定，结果按函数地址缓存）。
- **栈区域校验**：用 `mach_vm_region(task, &addr, &size, VM_REGION_BASIC_INFO_64, ...)` 取 `sp` 所在区域，要求 `VM_PROT_WRITE`，并把 `[region_start, region_end)` 作为回溯边界。否则一个被污染的 fp 会把你带进堆区、映射区，读出一串看似合法的垃圾地址。主线程栈与各 pthread 栈是不同 region，正好可以区分。
- **读内存统一用 `mach_vm_read_overwrite`**，即使是同进程（`pid == getpid()`）。不要直接解引用：异常的 fp 链随时可能指向未映射页，直接 `*(uint64_t*)fp` 会把整个进程带走（调试器自己崩了）。
- **批量预读**：帧数多时每次 16 字节的系统调用偏多，可一次读 `[sp, min(sp+8KB, stack_end))` 到本地缓冲，再在缓冲内解码，既快又能保证"同一时刻的栈"一致性。
- **去重**：连续重复的 LR（thunk / 尾调用）只保留一个。
- **限制**：64 帧、读失败立即停、不抛异常。

### 4.2 P1：无 FP 代码的兜底（系统库 / JIT / Unity il2cpp）

按投入产出排序：

1. **Compact Unwind（`__TEXT,__unwind_info`）**：Apple 自己的编码，每个函数范围给出三种之一：①基于 FP 的编码（可算出 CFA 与保存的 LR 位置）②指向 `__eh_frame` 的 DWARF CFI 偏移 ③无 unwind 信息。系统库和 Xcode 产物基本都带这个表，能解决 4.1 里"叶子函数跳一层"和"无 FP"两类问题。
2. **`__eh_frame` DWARF CFI 解释器**：通用性最好、工作量最大。可复用参考实现：
   `参考源码/jailbreak/symbols.c:614 apply_eh_frame_sizes()`（CIE/FDE 解析、`read_uleb/read_sleb/read_encoded_value`）、`:881 parse_macho_header()`、`:1390 GetSymbolListFromFile()`。
3. **栈扫描（stack scanning）+ 返回地址合法性校验**：从 `sp` 向上扫描 8 字节字，若某字落在可执行区、且 `addr-4` 处是 `BL`/`BLR`，则视为候选返回地址。位掩码判断即可，无需分配：

   ```cpp
   static inline bool is_bl_or_blr(uint32_t insn) {
       if ((insn & 0xFC000000u) == 0x94000000u) return true;   // BL  imm26
       if ((insn & 0xFFFFFC1Fu) == 0xD63F0000u) return true;   // BLR Xn
       return false;
   }
   ```
   （仓库里已有 capstone 封装 `Sources/Services/Memory/ARM64Assembler.h` 的 `DisassembledInstruction.isBranchLink`，但它走 ObjC/堆分配，异常路径里只建议作为离线校验工具，不建议放进热路径。）
4. **明确标注失败**：JIT / il2cpp / 手写汇编帧回溯不到时，输出"到此为止"，并在 UI 侧标注 `unknown`，**不要伪造帧**。

### 4.3 PAC / arm64e

`Makefile:2` 目前是 `ARCHS = arm64`，但面向未来要注意：fp 链上保存的返回地址可能带 PAC 签名，`__fp`/`__lr` 同理。所有取出的指针都要先 strip（`__builtin_ptrauth_strip(ptr, ptrauth_key_return_address)` / `xpaci`），否则符号化会全部落到错误模块。展开接口里把 strip 做成一处统一函数，方便切换。

---

## 5. 可选：抓取"所有线程"的调用栈

- 现成积木：`native_api.mm:1397 enumerate_threads()` 已经返回每个线程的 `pc/sp/fp`（内部 `task_threads` + `thread_get_state`，`:1533`）。
- 但它内部会 `pthread_from_mach_thread_np`、读 `dispatch_queue_get_label`、`malloc`。
- **同进程挂起其他线程有死锁风险**：如果被挂起的线程正持有 malloc / dyld / dispatch 的锁，而我们随后又要 `malloc` 或调用 `_dyld_get_image_header`（会拿 dyld 锁），就会死锁。
- 因此若要支持全线程快照，必须：
  1. 模块表在 `startDebugWithPid:` 时**预先缓存**（`_dyld_*` 调用全部前置）；
  2. 展开路径**不分配内存**（固定缓冲 / 预分配数组）；
  3. 只 `thread_suspend` 非当前、非出错线程，读完立即 `thread_resume`，并限时。

建议 P0 只做出错线程（它本来就被内核冻结，零死锁风险），全线程快照放到 P2。

---

## 6. 符号化（配合调用栈展示）

| 级别 | 手段 | 说明 |
| --- | --- | --- |
| L0 | 模块名 + 偏移 | `AccessRegisterViewController.m:128-163` 已在做（`_dyld_get_image_header` + slide + `LC_SEGMENT_64` 求范围）；服务层可用 `Sources/Services/ModuleViewer.h` 的 `getModuleByAddress:` |
| L1 | `dladdr()` | 一行拿到导出符号名，代价极低 |
| L2 | 完整符号表 | `native_api.mm:1313 enumerate_symbols()` / `:1120 parse_macho_symbols_in_memory()` 直接在内存里解析 Mach-O `LC_SYMTAB`；"结束地址"可用下一个符号地址近似 |
| L3 | dSYM / DWARF 行号 | 超出当前范围，需要独立符号文件 |

L2 的已知问题：`native_api.mm:1161` 用 `base_address + symtab.symoff` 读符号表，把 **file offset 当成 vmaddr** 用。对独立 Mach-O 成立，对共享缓存里的 dylib（`fileoff != vmaddr`）会读偏。两条修法：按 `LC_SEGMENT_64` 的 `fileoff→vmaddr` 做换算；或直接复用参考实现的**基于文件**的解析器（`参考源码/jailbreak/symbols.c:1390`），它还顺带用 `__eh_frame` 补出了函数长度、处理了 stub 与 exports trie，比内存版更完整。

性能要求：**按模块缓存符号表**，不要每帧解析一次。

---

## 7. 落地改动清单

1. **新增** `Sources/Services/Debugger/DynaDbg/debugger/debugger_unwind.mm/.h`（或并入 `debugger_register.mm`）：
   - `unwind_fp_chain(task, pc, fp, sp, out, max)`
   - `stack_region_of(task, sp, &lo, &hi)`、`is_executable_addr(task, addr)`、`strip_pac()`
2. **`debugger_native_api.mm`**：导出 `get_call_stack_native(mach_port_t thread, uint64_t *out, int max)`（内部先 `thread_get_state` 拿 fp/sp/pc，或在 break state 下用 `thread_states_` 里的冻结快照）。
3. **`debugger.h` / `debugger_internal.h`**：声明新方法。
4. **`SSDebugger.h/.mm`**：
   - 在 `@interface SSDebugger()`（`SSDebugger.mm:120-130`）里把 `lastCallStack` 重新声明为 `readwrite`（或直接写 `_lastCallStack`），否则外部永远读到 nil；
   - `send_exception_info()` 内同步展开 → 转成 hex `NSArray<NSString *>` → 赋 `lastCallStack` → 放进 `userInfo[@"callStack"]`（补在 `SSDebugger.mm:85-93` 那个字典里）。
5. **`debugger_types.h` + `exception_queue.mm`**（可选，走 `pollExceptions` 的路径）：
   - `ExceptionInfo` 加 `std::vector<uint64_t> call_stack;`
   - `convertFromNative()` 填充，`toJson()`（`exception_queue.mm:130`）输出 `"call_stack":["0x..."]`。
6. **UI（可选）**：`TracePage.h` 的 `SSTrackRecord` 加 `callStack` 字段以便列表直接展示；`AccessRegisterViewController.m:165-180 analyzeAddress:` 基础上加符号名。
7. **`Makefile`**：**无需改动**。`DynaDbg/debugger/*.mm` 走 `SSDebugger.mm` 的 `#include`
   模式（同一个编译单元），登记到 `ss_FILES` 会导致重复符号。
   （只有 `DynaDbg/debugger/exception_queue.mm` 是独立编译单元，因为它没有被 include。）
8. **新增测试** `tests/unwind_fp_chain_test.py`：算法级回归测试，`g++` + 桩即可运行，不需要 iPhone / Xcode。

---

## 8. 性能与风险

1. 每次异常约 20~60 次 16 字节读；批量预读栈窗口后基本只是内存拷贝，微秒级。
2. **展开必须限时**：异常处理期间出错线程被内核冻结，展开越久，游戏越"卡"。硬上限 64 帧 + 读失败立即停。
3. **主线程命中时 UI 冻结**（`thread_suspend`），采集必须同步完成，不能等 UI 触发。
4. **禁止在异常线程 `dispatch_sync` 主队列**（主线程可能正是被冻结线程）→ 死锁。
5. **trace 模式**（每条指令一次异常，`debugger_trace.mm` / `trace_file.h`）下逐条展开会爆量。建议：只在 break state 抓、或按采样率/前 N 帧抓；`trace_file.h:49` 的 trace entry 已有 `sp`，如需扩展加栈也是同一思路，但必须限帧。
6. **JIT / il2cpp 帧**回溯不到属正常，别伪造。
7. 别在 handler 里做重分配/大对象拷贝：`send_exception_info` 已经在异常上下文里，尽量用栈缓冲。

---

## 9. 验证方法

1. 构造 3 层调用 `A → B → C`，在 B/C 里访问被监视地址，检查输出层次是否符合预期（注意 4.1 叶子函数的层次差异）。
2. 自检输出：`fp` 是否 16 对齐、是否落在 `sp` 所在 region、`lr` 是否落在 `__TEXT`。
3. 与 `lldb -p <pid>` 的 `bt` 对照同一时刻的调用栈。
4. 覆盖场景：主线程、GCD 工作线程（栈顶通常是 `_pthread_wqthread`/`start_wqthread`）、深层递归（验证 64 帧截断）、Unity il2cpp / JIT（预期在 JIT 帧停下并标注 unknown）。
5. **无需设备**：`python3 tests/unwind_fp_chain_test.py` —— 用桩替换 mach API，对 `debugger_unwind.mm` 的真实源码跑 17 项断言（正常链 / 截断 / 对齐 / 越界 / 自环 / 读失败 / 去重 / LR 兜底 / 按线程抓取），当前全部通过。

---

## 10. 建议实施顺序

- **P0（半天~1 天）**：FP 链回溯 + `send_exception_info` 接线 + `userInfo[@"callStack"]`，UI 立即能看到调用栈。覆盖大多数 Xcode/系统库栈帧。
- **P1（1~2 天）**：Compact Unwind（`__unwind_info`）解码 + 叶子函数纠正 + 栈扫描兜底 + PAC strip。
- **P2**：全线程快照（预缓存模块表 + 无分配展开）、符号名展示（复用/修正 L2 或参考 `symbols.c`）、trace 模式按采样抓栈。


---

## 11. 执行断点（函数调用捕获）实现状态

目标场景：**让游戏在调用某个函数时被抓到**（例如 PvZ 的"拾取阳光"），并立刻看到"谁调用了它"。

### 已实现

| 能力 | 位置 |
| --- | --- |
| 执行断点注册表（address → 软件/硬件、目标命中数、已命中数） | `Sources/Services/Debugger/SSDebugger.mm` 的 `setFunctionBreakpoint:software:hitCount:` 等 |
| 命中回调：按异常类型拆分通知（观察点 / 执行断点各一条） | `SSDebugger.mm` 的 `send_exception_info`，新通知 `kSSDebuggerDidHitBreakpointNotification` |
| 命中即带寄存器 + 调用栈（复用 P0 的 FP 链展开） | 同上；userInfo 含 `registers`、`callStack`、`breakpoint{software,hitCount}` |
| 命中即弹窗显示寄存器/调用栈 | `Sources/UI/Pages/BreakpointHitPresenter.m`（复用 `AccessRegisterViewController`） |
| "继续"出口（不恢复就会永久冻住游戏） | `AccessRegisterViewController.showsResumeControls` + `SSDebugger.continueStoppedThread` |
| UI 入口：内存页汇编视图长按 → 设/移除执行断点 | `Sources/UI/Pages/MemoryPage+AssemblyActions.m` |
| 原生"继续最后被断住的线程"（不依赖异常消息端口） | `Debugger::continue_last_stopped_thread()` |

### 顺带修掉的三个真实问题

1. **命中通知缺失**：原先软件/硬件断点命中时线程被 `thread_suspend`，但 UI 从不发通知，等于"游戏卡死且没有任何提示"。
2. **没有恢复路径**：`continueExecution:` / `singleStep:` 全仓库没有任何 UI 调用者；现在寄存器页提供"继续"，
   且页面被关闭时自动继续，避免永久冻结。
3. **硬件断点无法越过**：`continue_execution` 只处理了软件断点的"单步越过再补回 BRK"；
   硬件断点在 break state 下 BCR 仍武装、PC 又停在断点地址，`thread_resume` 会立刻再次命中。
   现在会先摘 BCR + 开单步，再由既有的 `HardwareBreakpointContinue` 分支重新武装。

### 使用步骤（以"抓取阳光函数"为例）

1. 扫到阳光数量地址 → 在"访问"页给它下**写观察点**（观察点命中不暂停，游戏不会卡）。
2. 命中后进入"访问详情 → 寄存器"，底部就是**调用栈**；记录写入指令的 PC。
3. 内存页汇编视图定位该 PC 所在函数的入口（向前找 `stp x29, x30, [sp, #-N]!` 等序言）。
4. 在入口指令上**长按 → 设执行断点(软件)**；再点一次阳光：
   - 默认（暂停）：自动弹出寄存器 + 调用栈页面 —— 直接看到"谁调用了它"，页面左上角有「继续」；
   - 若想无感收集（函数每帧都被调用）：选「设执行断点(软件·命中不停顿)」，只发通知、不暂停。
5. 确认是目标函数后，若要自动化，再按第 4 节的 inline hook 路线把它替换成自己的实现。

### 仍然存在的限制

- 硬件执行断点只有 4 个左右硬件槽位，且**新创建的线程不会继承**；函数断点请优先用软件断点。
- 软件断点需要代码页可写：`write_memory_native` 目前只请求 `READ|WRITE`，建议补 `VM_PROT_COPY`
  （`Sources/Services/Debugger/DynaDbg/core/native_api.mm`）；失败时 UI 会提示改试硬件断点。
- 观察点 BAS 编码疑似少移一位（`debugger_watchpoint.mm` 的 `len_field`），1 字节观察点会永不命中，
  4/8 字节只覆盖前半段；走"观察点找写入指令"这条路时优先用 4 字节。

---

## 12. MCP 桥（让 AI 直接调用这套调试器）

设备侧新增 `Sources/Services/Remote/MCPBridge.mm`：一个"一行 JSON 进、一行 JSON 出"的 TCP 服务
（`0.0.0.0:27801`，默认口令 `igg-mcp-27801`），把内存读写/反汇编/数值搜索/观察点/执行断点/命中记录/调用栈
暴露成命令；MCP 协议本身由 PC 侧的 `tools/mcp/iosgg_mcp_server.js`（零依赖 Node）翻译，
DSH 通过 `@deepseek-ai/dsh-mcp-client`（stdio）挂载，工具名形如 `mcp__iosgg__iosgg_set_watchpoint`。

要点：
- **AI 无法被推送**：命中记录存在环形缓冲里，AI 通过 `iosgg_recent_hits` 主动轮询。
- **默认不暂停**：MCP 下 `stopExecution` 默认 false，避免 AI 忘了 `iosgg_continue` 把游戏卡死。
- 细节、部署步骤与排障见 `tools/mcp/README.md`。
