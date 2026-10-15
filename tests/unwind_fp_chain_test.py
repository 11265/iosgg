#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
debugger_unwind.mm 的算法级回归测试（无需 iOS 设备 / Xcode）

做法：用桩替换掉 mach 系列 API（mach_vm_region / mach_vm_read_overwrite /
thread_get_state ...），再造一条合成的 ARM64 frame pointer 链，直接编译并运行
**仓库里的真实源文件**（只去掉 #include、关闭 ptrauth 与 arm64 条件编译），
因此验证的是实际落地的代码，而不是复制品。

用法：
    python3 tests/unwind_fp_chain_test.py

依赖：g++（Linux / macOS 均可），退出码 0 表示全部通过。

栈布局约定（ARM64 栈向低地址增长）：sp 是当前帧的最低地址，fp >= sp。
"""

import io
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(
    os.path.join(HERE, "..", "Sources", "Services", "Debugger", "DynaDbg", "debugger",
                 "debugger_unwind.mm")
)

HARNESS_HEAD = r'''
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <vector>

// ===================== mach / debugger API 桩 =====================
typedef int kern_return_t;
typedef unsigned int mach_port_t;
typedef uint64_t mach_vm_address_t;
typedef uint64_t mach_vm_size_t;
typedef unsigned int mach_msg_type_number_t;
typedef int vm_prot_t;
typedef int vm_region_flavor_t;
typedef void *vm_region_info_t;

#define KERN_SUCCESS 0
#define KERN_FAILURE 5
#define MACH_PORT_NULL 0
#define VM_PROT_READ 1
#define VM_PROT_WRITE 2
#define VM_PROT_EXECUTE 4
#define VM_REGION_BASIC_INFO_64 9
#define VM_REGION_BASIC_INFO_COUNT_64 9
#define ARM_THREAD_STATE64 6
#define ARM_THREAD_STATE64_COUNT 68

struct vm_region_basic_info_data_64_t {
    vm_prot_t protection;
};

enum LogLevel { LOG_ERROR = 1, LOG_WARN = 2, LOG_INFO = 3, LOG_DEBUG = 4, LOG_TRACE = 5 };

static int debug_log(LogLevel level, const char *format, ...) {
    (void)level; (void)format; return 0;
}
static const char *mach_error_string(kern_return_t kr) { (void)kr; return "stub-error"; }
static mach_port_t mach_task_self(void) { return 1; }
static kern_return_t mach_port_deallocate(mach_port_t task, mach_port_t name) {
    (void)task; (void)name; return KERN_SUCCESS;
}

struct FakeRegion { uint64_t start, end; vm_prot_t prot; };
static std::vector<FakeRegion> g_regions;
static std::map<uint64_t, uint8_t> g_bytes;

static kern_return_t mach_vm_region(mach_port_t task, mach_vm_address_t *address,
                                    mach_vm_size_t *size, vm_region_flavor_t flavor,
                                    vm_region_info_t info, mach_msg_type_number_t *count,
                                    mach_port_t *object_name) {
    (void)task; (void)flavor; (void)count;
    *object_name = MACH_PORT_NULL;
    uint64_t addr = *address;
    for (size_t i = 0; i < g_regions.size(); i++) {
        const FakeRegion &r = g_regions[i];
        if (addr >= r.start && addr < r.end) {
            *address = r.start;
            *size = r.end - r.start;
            ((vm_region_basic_info_data_64_t *)info)->protection = r.prot;
            return KERN_SUCCESS;
        }
    }
    return KERN_FAILURE;
}

static kern_return_t mach_vm_read_overwrite(mach_port_t task, mach_vm_address_t address,
                                            mach_vm_size_t size, mach_vm_address_t buffer,
                                            mach_vm_size_t *out_size) {
    (void)task;
    for (mach_vm_size_t i = 0; i < size; i++) {
        if (g_bytes.find(address + i) == g_bytes.end()) { *out_size = 0; return KERN_FAILURE; }
    }
    for (mach_vm_size_t i = 0; i < size; i++) {
        ((uint8_t *)buffer)[i] = g_bytes[address + i];
    }
    *out_size = size;
    return KERN_SUCCESS;
}

typedef struct {
    uint64_t __x[29];
    uint64_t __fp;
    uint64_t __lr;
    uint64_t __sp;
    uint64_t __pc;
    uint64_t __cpsr;
} arm_thread_state64_t;
typedef void *thread_state_t;

static bool g_thread_state_valid = true;
static arm_thread_state64_t g_thread_state;

static kern_return_t thread_get_state(mach_port_t thread, int flavor, thread_state_t state,
                                      mach_msg_type_number_t *count) {
    (void)thread; (void)flavor; (void)count;
    if (!g_thread_state_valid) return KERN_FAILURE;
    *(arm_thread_state64_t *)state = g_thread_state;
    return KERN_SUCCESS;
}

// ===================== 被测代码（来自仓库源文件） =====================
#include "body.inc"

// ===================== 测试脚手架 =====================
static int g_failures = 0;

static void expect_bool(const char *name, bool ok) {
    printf("%-46s %s\n", name, ok ? "PASS" : "FAIL");
    if (!ok) g_failures++;
}

static void put_word(uint64_t addr, uint64_t value) {
    for (int i = 0; i < 8; i++) g_bytes[addr + i] = (uint8_t)((value >> (8 * i)) & 0xFF);
}

static void put_frame(uint64_t fp, uint64_t prev_fp, uint64_t lr) {
    put_word(fp, prev_fp);
    put_word(fp + 8, lr);
}

static void check(const char *name, int count, const uint64_t *got, const uint64_t *expect,
                  int expect_count) {
    bool ok = (count == expect_count);
    for (int i = 0; ok && i < count; i++) ok = (got[i] == expect[i]);
    printf("%-46s %s  (count=%d, expect=%d)\n", name, ok ? "PASS" : "FAIL", count, expect_count);
    if (!ok) {
        g_failures++;
        printf("     got   :");
        for (int i = 0; i < count; i++) printf(" 0x%llX", (unsigned long long)got[i]);
        printf("\n     expect:");
        for (int i = 0; i < expect_count; i++) printf(" 0x%llX", (unsigned long long)expect[i]);
        printf("\n");
    }
}

// 栈区域 [0x100000, 0x200000)，代码区域 [0x400000, 0x500000)
// sp = 0x1E0000（当前帧底），frame record 依次在 0x1E1000 / 0x1E2000 / 0x1E3000
#define CODE_LO 0x400000ULL
#define CODE_HI 0x500000ULL
#define SP      0x1E0000ULL
#define FP0     0x1E1000ULL
#define FP1     0x1E2000ULL
#define FP2     0x1E3000ULL
#define PC      0x400000ULL
'''

HARNESS_MAIN = r'''
int main(void) {
    g_regions.push_back({0x100000, 0x200000, VM_PROT_READ | VM_PROT_WRITE});
    g_regions.push_back({CODE_LO, CODE_HI, VM_PROT_READ | VM_PROT_EXECUTE});

    uint64_t out[200];
    mach_port_t task = mach_task_self();

    printf("== 区域判定 ==\n");
    expect_bool("stack_region(sp) 为 true", unwind_stack_region(task, SP, nullptr, nullptr));
    expect_bool("stack_region(代码区) 为 false",
                !unwind_stack_region(task, CODE_LO, nullptr, nullptr));
    expect_bool("is_executable(代码区) 为 true",
                unwind_is_executable_address(task, CODE_LO + 0x123));
    expect_bool("is_executable(栈) 为 false", !unwind_is_executable_address(task, SP));
    expect_bool("is_executable(未映射) 为 false",
                !unwind_is_executable_address(task, 0x99999999ULL));

    printf("== FP 链展开 ==\n");
    g_bytes.clear();
    put_frame(FP0, FP1, 0x400100);
    put_frame(FP1, FP2, 0x400200);
    put_frame(FP2, 0x0, 0x400300);
    {
        uint64_t expect[] = {PC, 0x400100, 0x400200, 0x400300};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0, out, 64);
        check("正常 4 级链", n, out, expect, 4);
    }
    {
        uint64_t expect[] = {PC, 0x400100};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0, out, 2);
        check("max_frames 截断", n, out, expect, 2);
    }
    {
        uint64_t expect[] = {PC, 0x400100, 0x400200, 0x400300};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0, out, 1000);
        check("max_frames 超硬上限仍正确", n, out, expect, 4);
    }
    check("max_frames=0 返回 0", unwind_fp_chain(task, PC, FP0, SP, 0, out, 0), out, out, 0);
    check("out_frames=NULL 返回 0", unwind_fp_chain(task, PC, FP0, SP, 0, nullptr, 64), out, out, 0);

    printf("== 非法链防护 ==\n");
    g_bytes.clear();
    put_frame(FP0, FP1, 0xDEAD);
    {
        uint64_t expect[] = {PC, 0x400050};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0x400050, out, 64);
        check("首帧返回地址非法 -> LR 兜底", n, out, expect, 2);
    }
    {
        uint64_t expect[] = {PC};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0xDEAD, out, 64);
        check("首帧与 LR 都非法 -> 只剩 pc", n, out, expect, 1);
    }
    {
        uint64_t expect[] = {PC};
        int n = unwind_fp_chain(task, PC, 0x300000, SP, 0, out, 64);
        check("fp 不在栈区域 -> 只剩 pc", n, out, expect, 1);
    }
    {
        uint64_t expect[] = {PC};
        int n = unwind_fp_chain(task, PC, 0x1E0008, SP, 0, out, 64);
        check("fp 未 16 字节对齐 -> 只剩 pc", n, out, expect, 1);
    }
    {
        uint64_t expect[] = {PC};
        int n = unwind_fp_chain(task, PC, 0x1D0000, SP, 0, out, 64);
        check("fp 低于 sp -> 只剩 pc", n, out, expect, 1);
    }

    g_bytes.clear();
    put_frame(FP0, FP0, 0x400100);
    {
        uint64_t expect[] = {PC, 0x400100};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0, out, 64);
        check("fp 自环 -> 立即停止", n, out, expect, 2);
    }
    g_bytes.clear();
    put_frame(FP0, FP1, 0x400100);
    {
        uint64_t expect[] = {PC, 0x400100};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0, out, 64);
        check("下一级 record 读失败 -> 立即停止", n, out, expect, 2);
    }

    printf("== 去重 ==\n");
    g_bytes.clear();
    put_frame(FP0, FP1, 0x400100);
    put_frame(FP1, FP2, 0x400100);
    put_frame(FP2, 0x0, 0x400300);
    {
        uint64_t expect[] = {PC, 0x400100, 0x400300};
        int n = unwind_fp_chain(task, PC, FP0, SP, 0, out, 64);
        check("连续相同返回地址去重", n, out, expect, 3);
    }

    printf("== 按线程端口抓取 ==\n");
    g_bytes.clear();
    put_frame(FP0, FP1, 0x400100);
    put_frame(FP1, 0x0, 0x400200);
    g_thread_state = arm_thread_state64_t();
    g_thread_state.__pc = PC;
    g_thread_state.__fp = FP0;
    g_thread_state.__sp = SP;
    g_thread_state.__lr = 0;
    g_thread_state_valid = true;
    {
        uint64_t expect[] = {PC, 0x400100, 0x400200};
        int n = get_call_stack_for_thread_native(task, 2, out, 64);
        check("thread_get_state -> 展开", n, out, expect, 3);
    }
    g_thread_state_valid = false;
    check("thread_get_state 失败 -> 0 帧",
          get_call_stack_for_thread_native(task, 2, out, 64), out, out, 0);
    g_thread_state_valid = true;
    check("thread 端口为空 -> 0 帧",
          get_call_stack_for_thread_native(task, MACH_PORT_NULL, out, 64), out, out, 0);

    printf("\n%s（失败 %d 项）\n", g_failures == 0 ? "全部通过" : "存在失败", g_failures);
    return g_failures == 0 ? 0 : 1;
}
'''


def build_body():
    """从真实源文件生成测试用片段：去掉 #include，关闭 ptrauth / arm64 条件编译"""
    with io.open(SRC, "r", encoding="utf-8") as f:
        lines = f.readlines()
    out = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("#include"):
            continue
        if stripped == "#if __has_feature(ptrauth_calls)":
            line = line.replace("#if __has_feature(ptrauth_calls)", "#if 0")
        if stripped == "#if defined(__arm64__) || defined(__aarch64__)":
            line = line.replace("#if defined(__arm64__) || defined(__aarch64__)", "#if 1")
        out.append(line)
    return "".join(out)


def main():
    if not os.path.isfile(SRC):
        print("找不到被测源文件: %s" % SRC)
        return 1

    work = tempfile.mkdtemp(prefix="dsh_unwind_test_")
    with io.open(os.path.join(work, "body.inc"), "w", encoding="utf-8") as f:
        f.write(build_body())
    with io.open(os.path.join(work, "harness.cpp"), "w", encoding="utf-8") as f:
        f.write(HARNESS_HEAD + HARNESS_MAIN)

    binary = os.path.join(work, "unwind_test")
    compile_cmd = ["g++", "-std=c++17", "-Wall", "-Wextra", "-Wno-unused-parameter",
                   "-o", binary, os.path.join(work, "harness.cpp")]
    print("被测源文件: %s" % SRC)
    print("$ " + " ".join(compile_cmd))
    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode != 0:
        print("编译失败")
        return 1

    print("\n$ ./unwind_test")
    run = subprocess.run([binary], capture_output=True, text=True)
    sys.stdout.write(run.stdout)
    sys.stderr.write(run.stderr)
    return run.returncode


if __name__ == "__main__":
    sys.exit(main())
