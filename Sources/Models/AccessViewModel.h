#import <Foundation/Foundation.h>
#import "Modules/Debugger/SSDebugger.h"

NS_ASSUME_NONNULL_BEGIN

@class AccessRecord;

extern NSNotificationName const AccessViewModelDidUpdateNotification;
extern NSNotificationName const AccessViewModelDebugStateChangedNotification;

@interface AccessViewModel : NSObject

@property (nonatomic, readonly) NSArray<AccessRecord *> *records;
@property (nonatomic, readonly) BOOL isDebugging;
@property (nonatomic, readonly) NSUInteger watchpointCount;

/// 硬件观察点槽位上限（ARM64 通常为 4）
@property (nonatomic, readonly) NSUInteger slotLimit;

#pragma mark - 添加/删除

- (void)addWatchpoint:(uint64_t)address type:(SSBreakpointType)type;
- (BOOL)addWatchpoint:(uint64_t)address
                 type:(SSBreakpointType)type
                error:(NSError * _Nullable * _Nullable)error;

- (void)removeWatchpointAtIndex:(NSUInteger)index;
- (void)removeAllWatchpoints;

#pragma mark - 启停/类型

- (void)setEnabled:(BOOL)enabled forAddress:(uint64_t)address;
- (BOOL)setEnabled:(BOOL)enabled
        forAddress:(uint64_t)address
             error:(NSError * _Nullable * _Nullable)error;

- (void)setType:(SSBreakpointType)type forAddress:(uint64_t)address;
- (BOOL)setType:(SSBreakpointType)type
     forAddress:(uint64_t)address
          error:(NSError * _Nullable * _Nullable)error;

#pragma mark - 调试器

- (void)startDebugging;
- (void)stopDebugging;
- (void)toggleDebugging;

#pragma mark - 查询

- (AccessRecord * _Nullable)recordAtIndex:(NSUInteger)index;
- (AccessRecord * _Nullable)recordForAddress:(uint64_t)address;
- (NSInteger)indexOfRecord:(AccessRecord *)record;

/// 清零某个地址的命中历史与当前值
- (void)resetHitCountForAddress:(uint64_t)address;

- (void)syncWithDebugger;

@end

NS_ASSUME_NONNULL_END
