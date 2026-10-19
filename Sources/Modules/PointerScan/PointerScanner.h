/*
 * ============================================================================
 *  指针链扫描（pointer chain scan）—— 本节代码标识
 *    ID      : 0CA2-4AD8-8E17-C3746067D85A
 *    日期时间: 2026-10-16 02:40:18
 *    引擎    : External/ptrscan/src（fast_ptrscan 源码，in-process）
 *    说明    : 区域枚举/索引/扫描/结果导出都在这里，UI 在 PointerScanPage，
 *              结果查看与两次对比在 FilterPage。
 * ============================================================================
 */

#import <Foundation/Foundation.h>

@interface PointerChainNode : NSObject <NSSecureCoding>
@property (nonatomic, assign) uint64_t address;      // The address where the pointer is located
@property (nonatomic, assign) uint64_t value;        // The value at that address (points to next node)
@property (nonatomic, assign) int64_t offset;        // value + offset = next_node.address
@property (nonatomic, strong) PointerChainNode *next; // Points to the next node (closer to target)
@property (nonatomic, strong) NSString *moduleName;  // Module name if address is static
@property (nonatomic, assign) uint64_t moduleBase;   // Module base address
@property (nonatomic, assign) BOOL isBase;           // YES if this is a static base address
@end

@class PtrScanOptions;

@interface PointerScanner : NSObject

+ (instancetype)sharedScanner;
- (void)startScan:(uint64_t)targetAddress 
         maxLevel:(int)maxLevel 
        maxOffset:(uint64_t)maxOffset 
       completion:(void(^)(NSString *resultsFilePath, NSUInteger count))completion
    progressBlock:(void(^)(float progress, NSString *status))progressBlock
    foundResultBlock:(void(^)(NSUInteger count))foundResultBlock;

/* 带完整参数的入口：参数说明见 PtrScanBridge.h 的 PtrScanOptions */
- (void)startScanWithOptions:(PtrScanOptions *)options
                  completion:(void(^)(NSString *resultsFilePath, NSUInteger count))completion
               progressBlock:(void(^)(float progress, NSString *status))progressBlock
            foundResultBlock:(void(^)(NSUInteger count))foundResultBlock;

- (void)stopScan;

/* 最近一次的结果文件（tmp 里最新的 pointer_scan_*.txt），供“筛选/查看结果”兜底 */
- (NSString *)latestResultsPath;

@end
