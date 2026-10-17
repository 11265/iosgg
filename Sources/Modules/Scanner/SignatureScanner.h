#ifndef 特征码搜索_h
#define 特征码搜索_h

#import <stddef.h>
#import <stdint.h>
#import <stdbool.h>
#import <mach/mach.h>

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

#ifdef __cplusplus
}
#endif

#endif // 特征码搜索_h 