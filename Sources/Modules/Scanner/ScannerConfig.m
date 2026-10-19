#import "Modules/Scanner/Scanner.h"
#import "Services/LogService.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <Foundation/Foundation.h>
#import <unistd.h>
#import <sys/stat.h>
#import <errno.h>
#import <dirent.h>
#import <pthread.h>
#import <stdatomic.h>

/*
 * 扫描器状态 / 文件辅助（Objective-C）。
 *
 * 纯算法（比较值、分块扫描）已移到 Sources/Core/Algorithms/SSScanCore.cpp；
 * 这里只保留依赖 Foundation、NSUUID、NSFileManager 的胶水代码。
 *
 * 全局状态由 ScannerState 单例承载（见 ScannerState.h）。
 */

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
