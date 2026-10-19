#ifndef SSMemoryBridge_h
#define SSMemoryBridge_h

/*
 * Shared Core 的 C ABI。
 *
 * Objective-C 模块（UI / Scanner / SignatureScanner / PointerChainParser）只
 * 依赖这组函数，不直接调用 mach_vm_*，也不持有 Mach Task Port。
 *
 * 实现：Sources/Core/Memory/SSMemoryBridge.mm，内部使用 MachProcessSession +
 * IMemoryReader / IMemoryWriter。
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t startAddress;
    uint64_t endAddress;
    uint64_t size;
    bool readable;
    bool writable;
    bool executable;
} SSMemoryRegionInfo;

typedef enum {
    SSMemoryProtRead = 1u << 0,
    SSMemoryProtWrite = 1u << 1,
    SSMemoryProtExecute = 1u << 2,
    SSMemoryProtCopy = 1u << 3
} SSMemoryProt;

/// 读取当前 Shared Core 会话；返回 false 表示会话不可用。
bool SSMemoryRead(uint64_t address, void* buffer, size_t size, size_t* bytesRead);
bool SSMemoryWrite(uint64_t address, const void* buffer, size_t size, size_t* bytesWritten);
bool SSMemoryProtect(uint64_t address, size_t size, uint32_t protection);

/*
 * 顺序枚举内存区域。cursor 第一次传 0，之后传上一次的值。
 * writableOnly=true 时只返回可写区域；返回 false 表示枚举结束。
 */
bool SSMemoryNextRegion(uint64_t* cursor, bool writableOnly, SSMemoryRegionInfo* out);

/// 查询包含 address 的区域（等价于 mach_vm_region）。
bool SSMemoryRegionAt(uint64_t address, SSMemoryRegionInfo* out);

/// 当前 Shared Core 会话的 pid（通常是本进程）。
pid_t SSMemoryPid(void);

#ifdef __cplusplus
}
#endif

#endif // SSMemoryBridge_h
