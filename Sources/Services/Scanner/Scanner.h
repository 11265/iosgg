#ifndef 搜索_H
#define 搜索_H

#import <stddef.h>
#import <stdint.h>
#import <stdbool.h>
#import <mach/mach.h>
#import <stdatomic.h>
#import "Services/ProcessMemory.h"

// 数据类型枚举
typedef enum {
    类型_字节 = 0,    // 1字节
    类型_短整数 = 1,  // 2字节
    类型_整数 = 2,    // 4字节
    类型_长整数 = 3,  // 8字节
    类型_浮点 = 4,    // 4字节
    类型_双精度 = 5,  // 8字节
    类型_指针 = 6     // 8字节 (64位指针)
} 数据类型;

// 兼容旧代码的类型定义
typedef 数据类型 SearchDataType;
#define SearchDataTypeU8 类型_字节
#define SearchDataTypeI16 类型_短整数
#define SearchDataTypeI32 类型_整数
#define SearchDataTypeI64 类型_长整数
#define SearchDataTypeF32 类型_浮点
#define SearchDataTypeF64 类型_双精度
#define SearchDataTypePtr 类型_指针

// 对比类型枚举
typedef enum {
    精确 = 0,        // 精确匹配
    变化 = 1,        // 值发生变化
    不变 = 2,        // 值保持不变
    增加了 = 3,      // 值增加
    减少了 = 4,      // 值减少
    增加了多少 = 5,  // 值增加指定数量
    减少了多少 = 6,  // 值减少指定数量
    区间 = 7,        // 值在指定区间内
    未知 = 9
} 对比类型;

// 搜索模式枚举
typedef enum {
    未搜索 = 0,
    模式二 = 1
} 搜索模式;

// 地址值对结构体
typedef struct {
    uint64_t address;  // 内存地址
    uint8_t bytes[8];  // 原始字节数据
} AddressValuePair;

// 内存条目结构体
typedef struct {
    mach_vm_address_t address;
    uint64_t file_offset;     // 在全局转储文件中的偏移量
    size_t compressed_size;   // 压缩后大小（未压缩时 == uncompressed_size）
    size_t uncompressed_size;
    bool is_first;
    bool is_compressed;       // true=LZ4压缩, false=原始数据（低内存降级）
    uint8_t bytes[8];         // 原始字节数据
} MemoryEntry;

// 数值联合体
typedef union {
    uint8_t bytes[8];  // 原始字节数据
    struct {
        int min;
        int max;
    } range_i;
    struct {
        int64_t min;
        int64_t max;
    } range_l;
    struct {
        float min;
        float max;
    } range_f;
    struct {
        double min;
        double max;
    } range_d;
    int i;
    float f;
    double d;
    uint8_t b;
    int16_t s;
    int64_t l;
} 数值;

// 内存范围结构体
typedef struct {
    mach_vm_address_t start;
    mach_vm_address_t end;
} AddressRange;


// 内存扫描器结构体
typedef struct {
    int id;
    mach_vm_address_t range_start;  
    mach_vm_address_t range_end;    
    void* previous_values;
} MemoryScanner;

// 搜索结果结构体
typedef struct {
    size_t count;
    char* result_file_path;
} SearchResult;

// 回调函数类型定义（必须在 ScannerState.h 导入之前定义）
typedef void (*SearchResultCallback)(uint64_t* results, size_t count, SearchDataType type);

// 向后兼容宏 —— 所有全局状态已封装到 ScannerState 单例
#import "Services/Scanner/ScannerState.h"

#define MEMORY_RANGE_START    ([ScannerState shared].memoryRangeStart)
#define MEMORY_RANGE_END      ([ScannerState shared].memoryRangeEnd)
#define global_scan_id        ([ScannerState shared].scanId)
#define global_dump_file_path ([ScannerState shared].dumpFilePath)
#define compressed_data       ([ScannerState shared].compressedData)
#define global_compressed_size ([ScannerState shared].compressedSize)
#define 当前搜索模式           ([ScannerState shared].currentSearchMode)
#define global_scanner         ([ScannerState shared].scanner)
#define global_memory           ([ScannerState shared].memory)
#define global_memory_count     ([ScannerState shared].memoryCount)
#define global_memory_capacity  ([ScannerState shared].memoryCapacity)
#define global_mutex            (*[[ScannerState shared] mutexPtr])
#define global_result_count     (*[[ScannerState shared] resultCountPtr])
#define search_results          ([ScannerState shared].searchResults)
#define 当前数据类型             ([ScannerState shared].currentDataType)
#define search_callback         ([ScannerState shared].callback)

// 核心比较函数
bool 比较值(const void* current, const void* previous, const void* target, 数据类型 data_type, 对比类型 type);

#ifdef __cplusplus
extern "C" {
#endif

void 搜索模式二(数值 target, 数据类型 data_type, 对比类型 type);
void 设置搜索回调(SearchResultCallback callback);
char* 生成扫描id(void);
void 清理搜索(void);
char* 创建临时文件(void);
void 删除临时文件(const char* path);
bool 是有效内存区域(vm_region_submap_info_data_64_t info);
MemoryScanner* 创建扫描器(void);
void 释放扫描器(MemoryScanner* scanner);
size_t 获取类型大小(数据类型 type);



#ifdef __cplusplus
}
#endif

#define BLOCK_SIZE (16 * 1024 * 1024)  // 16MB 的块大小

#endif // 搜索_H
