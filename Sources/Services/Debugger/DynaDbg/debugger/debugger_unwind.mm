/**
 * @file debugger_unwind.mm
 * @brief ARM64 调用栈（backtrace）回溯实现 —— 基于 frame pointer 链
 *
 * 设计要点：
 *   1. 只使用 mach 系统调用与栈上缓冲：不分配内存、不加锁、不抛异常，
 *      可以在 Mach 异常处理线程里、出错线程被内核冻结的窗口内安全调用。
 *   2. 每一步都做合法性校验（fp 16 字节对齐、落在 sp 所在的可写区域、严格递增、
 *      返回地址必须落在可执行区域），避免被污染的 fp 把回溯带进堆区读到一堆垃圾。
 *   3. 读内存统一走 mach_vm_read_overwrite：即使调试的是自身进程也不用裸指针解引用，
 *      否则一个野指针会把调试器自己带崩。
 *
 * 已知限制（P0）：
 *   - 未建立 frame record 的叶子函数会让上一层调用者"跳帧"（此时 x29 仍指向调用者的
 *     frame record）。彻底修正需要 Compact Unwind（__unwind_info）或 DWARF CFI。
 *   - JIT / il2cpp 等既无 CFI 又无 FP 约定的代码，回溯到边界即停，不做伪造。
 */

#include "debugger_internal.h"

#include <mach/mach.h>
#include <mach/vm_region.h>

#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

// =============================================================================
// 常量
// =============================================================================

// 硬上限：无论调用方要求多少帧，都不超过这个数量
static const int kUnwindMaxFramesHardLimit = 128;

// 合理的栈区域大小上限（主线程栈 8MB / 子线程栈 512KB），用于排除堆、JIT 等区域
static const uint64_t kUnwindMaxStackRegionSize = 64ULL * 1024 * 1024;

// =============================================================================
// 内部工具
// =============================================================================

/// 去掉 arm64e 指针认证（PAC）签名位；非 arm64e 平台上是空操作
static inline uint64_t unwind_strip_pac_inline(uint64_t value)
{
#if __has_feature(ptrauth_calls)
    return (uint64_t)__builtin_ptrauth_strip((void *)value, ptrauth_key_return_address);
#else
    return value;
#endif
}

/// 查询 address 所在的 VM 区域，返回区域范围与保护属性
static bool unwind_region_of(mach_port_t task, uint64_t address, uint64_t *out_start,
                             uint64_t *out_end, vm_prot_t *out_protection)
{
    mach_vm_address_t region_address = (mach_vm_address_t)address;
    mach_vm_size_t region_size = 0;
    vm_region_basic_info_data_64_t basic_info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;

    memset(&basic_info, 0, sizeof(basic_info));

    kern_return_t kr = mach_vm_region(task, &region_address, &region_size, VM_REGION_BASIC_INFO_64,
                                      (vm_region_info_t)&basic_info, &info_count, &object_name);
    if (object_name != MACH_PORT_NULL)
    {
        mach_port_deallocate(mach_task_self(), object_name);
    }
    if (kr != KERN_SUCCESS)
    {
        return false;
    }
    if (address < (uint64_t)region_address ||
        address >= (uint64_t)region_address + (uint64_t)region_size)
    {
        return false;
    }

    if (out_start) *out_start = (uint64_t)region_address;
    if (out_end) *out_end = (uint64_t)region_address + (uint64_t)region_size;
    if (out_protection) *out_protection = basic_info.protection;
    return true;
}

/// 读取目标进程内存（不分配、不抛异常，失败返回 false）
static bool unwind_read_memory(mach_port_t task, uint64_t address, void *buffer, size_t size)
{
    mach_vm_size_t read_size = 0;
    kern_return_t kr =
        mach_vm_read_overwrite(task, (mach_vm_address_t)address, (mach_vm_size_t)size,
                               (mach_vm_address_t)buffer, &read_size);
    return kr == KERN_SUCCESS && read_size == (mach_vm_size_t)size;
}

// =============================================================================
// 对外接口
// =============================================================================

extern "C" uint64_t unwind_strip_pac(uint64_t pointer)
{
    return unwind_strip_pac_inline(pointer);
}

extern "C" bool unwind_is_executable_address(mach_port_t task, uint64_t address)
{
    uint64_t start = 0;
    uint64_t end = 0;
    vm_prot_t protection = 0;
    if (!unwind_region_of(task, address, &start, &end, &protection))
    {
        return false;
    }
    return (protection & VM_PROT_EXECUTE) != 0;
}

extern "C" bool unwind_stack_region(mach_port_t task, uint64_t address, uint64_t *out_start,
                                    uint64_t *out_end)
{
    uint64_t start = 0;
    uint64_t end = 0;
    vm_prot_t protection = 0;
    if (!unwind_region_of(task, address, &start, &end, &protection))
    {
        return false;
    }
    // 栈必须可写，且大小在合理范围内（排除堆 / JIT / 映射文件等区域）
    if ((protection & VM_PROT_WRITE) == 0)
    {
        return false;
    }
    if (end - start > kUnwindMaxStackRegionSize)
    {
        return false;
    }

    if (out_start) *out_start = start;
    if (out_end) *out_end = end;
    return true;
}

/**
 * ARM64 frame pointer 链回溯
 *
 * frame 0 = pc（触发异常/断点的指令本身），之后依次是各级返回地址。
 * lr 仅在首帧 frame record 不可用时作为兜底（叶子函数常见）。
 * 返回写入 out_frames 的帧数（至少 1 帧：pc 本身）。
 */
extern "C" int unwind_fp_chain(mach_port_t task, uint64_t pc, uint64_t fp, uint64_t sp, uint64_t lr,
                               uint64_t *out_frames, int max_frames)
{
    if (out_frames == nullptr || max_frames <= 0)
    {
        return 0;
    }
    if (max_frames > kUnwindMaxFramesHardLimit)
    {
        max_frames = kUnwindMaxFramesHardLimit;
    }

    int frame_count = 0;
    out_frames[frame_count++] = unwind_strip_pac_inline(pc);

    uint64_t stack_start = 0;
    uint64_t stack_end = 0;
    if (!unwind_stack_region(task, sp, &stack_start, &stack_end))
    {
        // 连 sp 所在区域都拿不到：不硬走，只返回 pc 这一帧
        return frame_count;
    }

    uint64_t current_fp = unwind_strip_pac_inline(fp);
    bool checked_first_record = false;

    while (frame_count < max_frames)
    {
        // 1) frame pointer 合法性：非空、16 字节对齐、不低于 sp、落在栈区域内
        if (current_fp == 0 || (current_fp & 0xF) != 0)
        {
            break;
        }
        if (current_fp < sp)
        {
            break;
        }
        if (current_fp < stack_start || current_fp + 16 > stack_end)
        {
            break;
        }

        // 2) 读 frame record：[fp] = 上一级 fp，[fp + 8] = 返回地址
        uint64_t record[2] = {0, 0};
        if (!unwind_read_memory(task, current_fp, record, sizeof(record)))
        {
            break;
        }

        uint64_t next_fp = unwind_strip_pac_inline(record[0]);
        uint64_t return_address = unwind_strip_pac_inline(record[1]);

        // 3) 首帧兜底：frame record 里的返回地址不可用时，改用寄存器里的 LR
        //    （线程入口 / 极浅调用链上 frame record 还没建立的情况）
        if (!checked_first_record)
        {
            checked_first_record = true;
            if (!unwind_is_executable_address(task, return_address))
            {
                uint64_t lr_value = unwind_strip_pac_inline(lr);
                if (lr_value != 0 && unwind_is_executable_address(task, lr_value))
                {
                    out_frames[frame_count++] = lr_value;
                }
            }
        }

        if (return_address == 0 || !unwind_is_executable_address(task, return_address))
        {
            break;
        }

        // 4) 去重（thunk / 尾调用可能连续出现相同返回地址）
        if (out_frames[frame_count - 1] != return_address)
        {
            out_frames[frame_count++] = return_address;
        }

        // 5) 必须严格递增，否则视为被污染的链，立即停止（防死循环）
        if (next_fp <= current_fp)
        {
            break;
        }
        current_fp = next_fp;
    }

    return frame_count;
}

/**
 * 按线程端口抓取调用栈（供 UI 按需 / 懒采集使用）
 *
 * 线程处于 break state（已被 thread_suspend）时结果最准确；
 * 线程在运行时只能拿到某一瞬间的快照，属于 best-effort。
 */
extern "C" int get_call_stack_for_thread_native(mach_port_t task, mach_port_t thread,
                                                uint64_t *out_frames, int max_frames)
{
#if defined(__arm64__) || defined(__aarch64__)
    if (thread == MACH_PORT_NULL || out_frames == nullptr || max_frames <= 0)
    {
        return 0;
    }

    arm_thread_state64_t thread_state;
    mach_msg_type_number_t state_count = ARM_THREAD_STATE64_COUNT;
    kern_return_t kr =
        thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&thread_state, &state_count);
    if (kr != KERN_SUCCESS)
    {
        debug_log(LOG_WARN, "get_call_stack_for_thread_native: thread_get_state failed: %s",
                  mach_error_string(kr));
        return 0;
    }

    mach_port_t task_port = (task == MACH_PORT_NULL) ? mach_task_self() : task;
    return unwind_fp_chain(task_port, thread_state.__pc, thread_state.__fp, thread_state.__sp,
                           thread_state.__lr, out_frames, max_frames);
#else
    (void)task;
    (void)thread;
    (void)out_frames;
    (void)max_frames;
    return 0;
#endif
}
