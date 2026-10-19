#ifndef ScannerKernel_h
#define ScannerKernel_h

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include "Modules/Scanner/Scanner.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 命中批次回调：内核每攒满一批就交出去，调用方不用再写"缓冲满了怎么办"的续扫逻辑
typedef void (*扫描提交)(void *上下文, const AddressValuePair *项, size_t 条数);

/// 只依赖当前值的比较：精确、区间
/// 实现：Sources/Core/Algorithms/SSScanCore.cpp（C++17）
size_t 扫描块_单值(const uint8_t *当前, size_t 字节数, uint64_t 基址,
                   数据类型 类型, 对比类型 操作, const 数值 *目标,
                   AddressValuePair *暂存, size_t 暂存容量,
                   扫描提交 提交, void *上下文);

/// 需要上一轮的值的比较：变化、不变、增加了、减少了、增加了多少、减少了多少
/// 实现：Sources/Core/Algorithms/SSScanCore.cpp（C++17）
size_t 扫描块_双值(const uint8_t *当前, const uint8_t *旧值, size_t 字节数, uint64_t 基址,
                   数据类型 类型, 对比类型 操作, const 数值 *目标,
                   AddressValuePair *暂存, size_t 暂存容量,
                   扫描提交 提交, void *上下文);

#ifdef __cplusplus
}
#endif
#endif
