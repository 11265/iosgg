/*
 * ============================================================================
 *  指针链扫描（pointer chain scan）—— 本节代码标识
 *    ID      : 0CA2-4AD8-8E17-C3746067D85A
 *    日期时间: 2026-10-16 02:40:18
 *    引擎    : External/ptrscan/libptrscan-ios-arm64.a（in-process 自扫描）
 *    说明    : 区域枚举/索引/扫描/结果导出都在这里，UI 在 PointerScanPage，
 *              结果查看与两次对比在 FilterPage。
 * ============================================================================
 */

#import "Services/Memory/PointerScanner.h"
#import "Services/Memory/PtrScanBridge.h"
#import "Services/LogService.h"

/*
 * 指针扫描对外接口。真正的引擎是 libptrscan（见 PtrScanBridge），这里只保留
 * 原来的调用方式，外加一个能传全部参数的入口。
 */

@implementation PointerChainNode

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (NSString *)description {
    if (self.isBase) {
        return [NSString stringWithFormat:@"[%@ + 0x%llX]", self.moduleName, self.address - self.moduleBase];
    }
    return [NSString stringWithFormat:@"0x%llX", self.address];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt64:self.address forKey:@"address"];
    [coder encodeInt64:self.value forKey:@"value"];
    [coder encodeInt64:self.offset forKey:@"offset"];
    [coder encodeObject:self.next forKey:@"next"];
    [coder encodeObject:self.moduleName forKey:@"moduleName"];
    [coder encodeInt64:self.moduleBase forKey:@"moduleBase"];
    [coder encodeBool:self.isBase forKey:@"isBase"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        self.address = [coder decodeInt64ForKey:@"address"];
        self.value = [coder decodeInt64ForKey:@"value"];
        self.offset = [coder decodeInt64ForKey:@"offset"];
        self.next = [coder decodeObjectForKey:@"next"];
        self.moduleName = [coder decodeObjectForKey:@"moduleName"];
        self.moduleBase = [coder decodeInt64ForKey:@"moduleBase"];
        self.isBase = [coder decodeBoolForKey:@"isBase"];
    }
    return self;
}

@end

@implementation PointerScanner

+ (instancetype)sharedScanner {
    static PointerScanner *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[PointerScanner alloc] init]; });
    return shared;
}

- (void)startScan:(uint64_t)targetAddress
         maxLevel:(int)maxLevel
        maxOffset:(uint64_t)maxOffset
       completion:(void(^)(NSString *resultsFilePath, NSUInteger count))completion
    progressBlock:(void(^)(float progress, NSString *status))progressBlock
  foundResultBlock:(void(^)(NSUInteger count))foundResultBlock
{
    PtrScanOptions *o = [[PtrScanOptions alloc] init];
    o.targetAddress       = targetAddress;
    o.maxDepth            = maxLevel > 0 ? maxLevel : 5;
    o.maxOffset           = maxOffset > 0 ? maxOffset : 0x1000;
    o.maxTargetsPerNode   = 8;      /* 默认每层保留 8 个候选，0 = 不限 */
    o.excludeNames        = @[ @"dyld_shared_cache" ];
    o.lowMemory           = YES;

    [self startScanWithOptions:o
                    completion:completion
                 progressBlock:progressBlock
              foundResultBlock:foundResultBlock];
}

- (void)startScanWithOptions:(PtrScanOptions *)options
                  completion:(void(^)(NSString *resultsFilePath, NSUInteger count))completion
               progressBlock:(void(^)(float progress, NSString *status))progressBlock
            foundResultBlock:(void(^)(NSUInteger count))foundResultBlock
{
    [[PtrScanBridge sharedBridge] scanWithOptions:options
        progress:^(float progress, NSString *status) {
            if (progressBlock) progressBlock(progress, status);
        }
        completion:^(PtrScanResult *result, NSError *error) {
            if (error) {
                [LoggingService log:@"[指针扫描] 失败: %@", error.localizedDescription];
                if (completion) completion(nil, 0);
                return;
            }
            if (foundResultBlock) foundResultBlock(result.chainCount);
            if (completion) completion(result.resultsFilePath, result.chainCount);
        }];
}

- (NSString *)latestResultsPath {
    return [[PtrScanBridge sharedBridge] latestResultsPath];
}

- (void)stopScan {
    [[PtrScanBridge sharedBridge] stop];
    [LoggingService log:@"[指针扫描] 已请求停止"];
}

@end
