#import "Services/Scanner/Scanner.h"
#import "External/lz4/lz4.h"
#import "Services/LogService.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <Foundation/Foundation.h>
#import <unistd.h>
#import <sys/stat.h>
#import <errno.h>
#import <dirent.h>
#import <dispatch/dispatch.h>
#import <pthread.h>
#import <stdatomic.h>
#import <sys/mman.h>
#import <fcntl.h>
#include <cmath>

// 全局状态已移至 ScannerState 单例（移除原先的 C 全局变量定义）

bool 是有效内存区域(vm_region_submap_info_data_64_t info) {
    return (info.protection & VM_PROT_WRITE) == VM_PROT_WRITE;
}

void 设置搜索回调(SearchResultCallback callback) {
    pthread_mutex_lock([[ScannerState shared] mutexPtr]);
    [ScannerState shared].callback = callback;
    pthread_mutex_unlock([[ScannerState shared] mutexPtr]);
}

char* 生成扫描id(void) {
    pthread_mutex_lock([[ScannerState shared] mutexPtr]);
    if ([ScannerState shared].scanId) {
        free([ScannerState shared].scanId);
    }
    NSString *uuid = [[NSUUID UUID] UUIDString];
    [ScannerState shared].scanId = strdup([uuid UTF8String]);
    pthread_mutex_unlock([[ScannerState shared] mutexPtr]);
    return [ScannerState shared].scanId;
}

MemoryScanner* 创建扫描器(void) {
    MemoryScanner* scanner = (MemoryScanner*)malloc(sizeof(MemoryScanner));
    if (!scanner) {
        [LoggingService log:@"创建扫描器失败：内存分配错误"];
        return NULL;
    }
    scanner->range_start = MEMORY_RANGE_START;
    scanner->range_end = MEMORY_RANGE_END;
    scanner->previous_values = NULL;
    return scanner;
}

void 释放扫描器(MemoryScanner* scanner) {
    if (!scanner) return;
    if (scanner->previous_values) free(scanner->previous_values);
    free(scanner);
}

size_t 获取类型大小(数据类型 type) {
    switch (type) {
        case 类型_字节: return sizeof(uint8_t);
        case 类型_短整数: return sizeof(int16_t);
        case 类型_整数: return sizeof(int32_t);
        case 类型_长整数: return sizeof(int64_t);
        case 类型_浮点: return sizeof(float);
        case 类型_双精度: return sizeof(double);
        case 类型_指针: return sizeof(uint64_t);
        default: return sizeof(int32_t);
    }
}

// 统一的比较值函数
bool 比较值(const void* current, const void* previous, const void* target, 数据类型 data_type, 对比类型 type) {
    if (!current) return false;
    
    size_t size = 获取类型大小(data_type);
    const uint8_t* curr = (const uint8_t*)current;
    const uint8_t* prev = (const uint8_t*)previous;
    const uint8_t* tgt = (const uint8_t*)target;



    // 区间比较
    if (type == 区间) {
        const 数值* value = (const 数值*)target;
        if (!value) return false;

        switch (data_type) {
            case 类型_字节: {
                uint8_t val = *(const uint8_t*)current;
                return val >= (value->range_i.min & 0xFF) && val <= (value->range_i.max & 0xFF);
            }
            case 类型_短整数: {
                int16_t val = *(const int16_t*)current;
                return val >= (int16_t)(value->range_i.min & 0xFFFF) && val <= (int16_t)(value->range_i.max & 0xFFFF);
            }
            case 类型_整数: {
                int32_t val = *(const int32_t*)current;
                return val >= value->range_i.min && val <= value->range_i.max;
            }
            case 类型_长整数: {
                int64_t val = *(const int64_t*)current;
                return val >= value->range_l.min && val <= value->range_l.max;
            }
            case 类型_浮点: {
                float val = *(const float*)current;
                return val >= value->range_f.min && val <= value->range_f.max;
            }
            case 类型_双精度: {
                double val = *(const double*)current;
                return val >= value->range_d.min && val <= value->range_d.max;
            }
            case 类型_指针: {
                uint64_t val = *(const uint64_t*)current;
                return val >= (uint64_t)value->range_l.min && val <= (uint64_t)value->range_l.max;
            }
        }
        return false;
    }

    // 精确匹配
    if (type == 精确) {
        return memcmp(curr, tgt, size) == 0;
    }

    // 需要前一个值的比较这行代码的作用是： 如果不存在旧值（prev 为空），则后续所有依赖于旧值的比较类型（变化、不变、增加、减少等）都直接判定为不匹配，防止空指针解引用导致程序崩溃
    if (!prev) return false;

    // 变化和不变
    if (type == 变化) {
        return memcmp(curr, prev, size) != 0;
    }
    if (type == 不变) {
        return memcmp(curr, prev, size) == 0 && memcmp(curr, "\0\0\0\0\0\0\0\0", size) != 0;
    }

    // 数值比较
    if (type == 增加了 || type == 减少了 || type == 增加了多少 || type == 减少了多少) {
        switch (data_type) {
            case 类型_字节: {
                uint8_t c = *(const uint8_t*)current;
                uint8_t p = *(const uint8_t*)previous;
                uint8_t t = tgt ? *(const uint8_t*)target : 0;
                
                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return (c > p) && ((c - p) == t);
                if (type == 减少了多少) return (p > c) && ((p - c) == t);
                break;
            }
            case 类型_短整数: {
                int16_t c = *(const int16_t*)current;
                int16_t p = *(const int16_t*)previous;
                int16_t t = tgt ? *(const int16_t*)target : 0;
                
                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return (int64_t)c - (int64_t)p == t;
                if (type == 减少了多少) return (int64_t)p - (int64_t)c == t;
                break;
            }
            case 类型_整数: {
                int32_t c = *(const int32_t*)current;
                int32_t p = *(const int32_t*)previous;
                int32_t t = tgt ? *(const int32_t*)target : 0;
                
                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return (int64_t)c - (int64_t)p == t;
                if (type == 减少了多少) return (int64_t)p - (int64_t)c == t;
                break;
            }
            case 类型_长整数: {
                int64_t c = *(const int64_t*)current;
                int64_t p = *(const int64_t*)previous;
                int64_t t = tgt ? *(const int64_t*)target : 0;
                
                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return (c - p) == t;
                if (type == 减少了多少) return (p - c) == t;
                break;
            }
            case 类型_浮点: {
                float c = *(const float*)current;
                float p = *(const float*)previous;
                float t = tgt ? *(const float*)target : 0;
                float epsilon = 0.0001f;
                
                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return std::fabs((c - p) - t) < epsilon;
                if (type == 减少了多少) return std::fabs((p - c) - t) < epsilon;
                break;
            }
            case 类型_双精度: {
                double c = *(const double*)current;
                double p = *(const double*)previous;
                double t = tgt ? *(const double*)target : 0;
                double epsilon = 0.0001;
                
                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return std::fabs((c - p) - t) < epsilon;
                if (type == 减少了多少) return std::fabs((p - c) - t) < epsilon;
                break;
            }
            case 类型_指针: {
                uint64_t c = *(const uint64_t*)current;
                uint64_t p = *(const uint64_t*)previous;
                uint64_t t = tgt ? *(const uint64_t*)target : 0;
                
                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return (int64_t)(c - p) == (int64_t)t;
                if (type == 减少了多少) return (int64_t)(p - c) == (int64_t)t;
                break;
            }
        }
        return false;
    }

    return false;
}

void 删除扫描目录(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([paths count] == 0) {
        [LoggingService log:@"无法获取缓存目录路径"];
        return;
    }
    NSString *cacheDir = [paths objectAtIndex:0];
    NSString *scanDir = [cacheDir stringByAppendingPathComponent:@"MemoryScans"];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:scanDir]) {
        if (![[NSFileManager defaultManager] removeItemAtPath:scanDir error:&error]) {
            [LoggingService log:@"删除扫描目录失败: %@", error];
        } else {
            [LoggingService log:@"成功删除扫描目录"];
        }
    }
}

void 清理搜索(void) {
    pthread_mutex_lock([[ScannerState shared] mutexPtr]);
    if ([ScannerState shared].scanner) {
        释放扫描器([ScannerState shared].scanner);
        [ScannerState shared].scanner = NULL;
    }
    if ([ScannerState shared].memory) {
        free([ScannerState shared].memory);
        [ScannerState shared].memory = NULL;
    }
    [ScannerState shared].memoryCount = 0;
    [ScannerState shared].memoryCapacity = 0;
    
    if ([ScannerState shared].dumpFilePath) {
        free([ScannerState shared].dumpFilePath);
        [ScannerState shared].dumpFilePath = NULL;
    }
    
    删除扫描目录();
    atomic_store([[ScannerState shared] resultCountPtr], 0);
    if ([ScannerState shared].scanId) {
        free([ScannerState shared].scanId);
        [ScannerState shared].scanId = NULL;
    }
    if ([ScannerState shared].compressedData) {
        free([ScannerState shared].compressedData);
        [ScannerState shared].compressedData = NULL;
    }
    [ScannerState shared].compressedSize = 0;
    [ScannerState shared].currentSearchMode = 未搜索;
    pthread_mutex_unlock([[ScannerState shared] mutexPtr]);
    [LoggingService log:@"搜索资源已清理完成"];
}

char* 创建临时文件(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([paths count] == 0) {
        [LoggingService log:@"无法获取缓存目录路径"];
        return NULL;
    }
    NSString *cacheDir = [paths objectAtIndex:0];
    NSString *scanDir = [cacheDir stringByAppendingPathComponent:@"MemoryScans"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:scanDir]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:scanDir
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&error]) {
            [LoggingService log:@"创建扫描目录失败: %@", error];
            return NULL;
        }
    }
    NSString *fileName = [NSString stringWithFormat:@"scan_%@", [[NSUUID UUID] UUIDString]];
    NSString *fullPath = [scanDir stringByAppendingPathComponent:fileName];
    if (![[NSFileManager defaultManager] createFileAtPath:fullPath contents:nil attributes:nil]) {
        [LoggingService log:@"无法创建临时文件: %@", fullPath];
        return NULL;
    }
    return strdup([fullPath UTF8String]);
}

void 删除临时文件(const char* path) {
    if (!path) return;
    NSString *filePath = [NSString stringWithUTF8String:path];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:filePath error:&error]) {
        [LoggingService log:@"删除临时文件失败 %s: %@", path, error];
    }
}
