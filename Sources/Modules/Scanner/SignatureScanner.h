#ifndef 特征码搜索_h
#define 特征码搜索_h

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

// 特征码搜索相关结构体
typedef struct {
    uint8_t byte;
    bool is_wildcard;
} PatternByte;

typedef struct {
    PatternByte* bytes;
    size_t length;
} SearchPattern;

// 回调函数类型定义
typedef void (*SignatureSearchCallback)(uint64_t* results, size_t count);

/// 每命中一条就回调一次，调用方自行决定保存/截断策略
typedef void (*SignatureMatchCallback)(void* context, uint64_t address);

// 修改宏名称以避免冲突
#define SIGNATURE_SEARCH_RANGE_START 0x100000000ULL  // 4GB
#define SIGNATURE_SEARCH_RANGE_END   0x300000000ULL  // 8GB

#ifdef __cplusplus
extern "C" {
#endif

// 公共函数声明
void 设置特征码搜索回调(SignatureSearchCallback callback);
SearchPattern* 解析特征码(const char* pattern);
void 释放特征码(SearchPattern* pattern);
void 搜索模式三(const char* pattern);

/*
 * 纯算法入口：在一个已经读入内存的缓冲区里跑 Sunday 匹配。
 *
 * 实现：Sources/Core/Algorithms/SSSignatureCore.cpp（C++17）。不碰 mach / ObjC，
 * 便于主机侧单元测试；区域枚举与内存读取仍由 SignatureScanner.m 负责。
 *
 * 返回命中总数；调用方通过回调自行决定保存/截断策略。
 */
size_t 扫描特征码缓冲区(const SearchPattern* pattern, const uint8_t* buffer, size_t size,
                        uint64_t base, SignatureMatchCallback on_match, void* context);

#ifdef __cplusplus
}
#endif

#endif // 特征码搜索_h
