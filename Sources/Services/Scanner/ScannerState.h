#import <Foundation/Foundation.h>
#import <stddef.h>
#import <stdint.h>
#import <stdbool.h>
#import <mach/mach.h>
#import <stdatomic.h>
#import "Services/Scanner/Scanner.h"

/// 内存安全的扫描器全局状态单例，封装原先的 C 全局变量
@interface ScannerState : NSObject

+ (instancetype)shared;

/// 获取 mutex 指针（用于 pthread_mutex_lock/unlock 等需要取地址的 API）
- (pthread_mutex_t *)mutexPtr;

/// 获取 resultCount 指针（用于 atomic_store / atomic_load 等需要取地址的 API）
- (atomic_size_t *)resultCountPtr;

#pragma mark - 内存范围

@property (nonatomic, assign) uint64_t memoryRangeStart;  // 默认 4GB
@property (nonatomic, assign) uint64_t memoryRangeEnd;    // 默认 8GB

#pragma mark - 扫描标识与路径

@property (nonatomic, assign) char* scanId;
@property (nonatomic, assign) char* dumpFilePath;
@property (nonatomic, assign) char* compressedData;
@property (nonatomic, assign) int compressedSize;

#pragma mark - 扫描器

@property (nonatomic, assign) 搜索模式 currentSearchMode;
@property (nonatomic, assign) MemoryScanner* scanner;
@property (nonatomic, assign) MemoryEntry* memory;
@property (nonatomic, assign) size_t memoryCount;
@property (nonatomic, assign) size_t memoryCapacity;

#pragma mark - 互斥锁与结果

@property (nonatomic, assign) pthread_mutex_t mutex;
@property (nonatomic, assign) atomic_size_t resultCount;
@property (nonatomic, assign) SearchResult* searchResults;

#pragma mark - 数据类型与回调

@property (nonatomic, assign) SearchDataType currentDataType;
@property (nonatomic, assign) SearchResultCallback callback;

@end
