#ifndef SSPointerChainCore_h
#define SSPointerChainCore_h

/*
 * 指针链核心（C ABI，实现为纯 C++17）。
 *
 * 目标是把“字符串 → 步骤数组 → 解引用求值”这段纯逻辑从 Objective-C
 * 里拿出来，内存读取通过回调注入，因此核心不依赖 mach / Foundation。
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SS_CHAIN_MAX_STEPS   64
#define SS_CHAIN_MODULE_MAX  256
#define SS_CHAIN_ERROR_MAX   256

typedef enum {
    SS_CHAIN_STEP_MODULE = 0,   // [模块 + 偏移]
    SS_CHAIN_STEP_ADDRESS = 1,  // 0x绝对地址
    SS_CHAIN_STEP_POINTER = 2   // +偏移（解引用后相加）
} SSChainStepType;

typedef struct {
    SSChainStepType type;
    uint64_t offset;
    char module[SS_CHAIN_MODULE_MAX];  // 已转小写；仅 module 步骤使用
} SSChainStep;

/// 读取一个 64 位指针；返回 0 表示成功，非 0 作为错误码（可直接传 kern_return_t）
typedef int (*SSChainReadFn)(uint64_t address, uint64_t *value, void *context);

/// 可选日志回调；核心只负责格式化，不直接依赖 LoggingService
typedef void (*SSChainLogFn)(const char *message, void *context);

/*
 * 解析表达式。成功返回步骤数（>0）；失败返回 0，并写入 error_code / error。
 * 支持的格式：
 *   [模块+偏移] -> +偏移 -> +偏移
 *   [模块+偏移]
 *   [模块]
 *   模块+偏移
 *   模块
 *   0x地址 + 偏移 + 偏移
 */
size_t ss_chain_parse(const char *expression, SSChainStep *steps, size_t capacity,
                      SSChainLogFn log, void *context,
                      int *error_code, char *error, size_t error_size);

/*
 * 按步骤求值。成功返回最终地址；失败返回 0，并写入 status / error。
 * module_base 只在 module 步骤使用。
 */
uint64_t ss_chain_resolve(const SSChainStep *steps, size_t count, uint64_t module_base,
                          SSChainReadFn read, SSChainLogFn log, void *context,
                          int *status, char *error, size_t error_size);

#ifdef __cplusplus
}
#endif

#endif // SSPointerChainCore_h
