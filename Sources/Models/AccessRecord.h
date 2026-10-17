#import <Foundation/Foundation.h>
#import "Modules/Debugger/SSDebugger.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const kAccessRecordDidUpdateNotification;

@interface AccessHit : NSObject
@property (nonatomic, assign) uint64_t value;
@property (nonatomic, assign) uint64_t instructionAddr;
@property (nonatomic, assign) uint64_t memoryAddress;
@property (nonatomic, assign) SSBreakpointType type;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) NSInteger hitCount;
@property (nonatomic, assign) uint32_t threadId;
@property (nonatomic, assign) uint8_t accessSize;
@property (nonatomic, strong, nullable) NSDictionary *registers;
@property (nonatomic, strong, nullable) NSArray *callStack;
@end

@interface AccessRecord : NSObject
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) uint64_t value;
@property (nonatomic, assign) BOOL hasValue;
@property (nonatomic, assign) uint64_t instructionAddr;
@property (nonatomic, assign) SSBreakpointType type;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) NSInteger hitCount;
@property (nonatomic, strong, nullable) NSDictionary *registers;
@property (nonatomic, strong, nullable) NSArray *callStack;

/// 最近一次命中的时间 / 线程
@property (nonatomic, strong, nullable) NSDate *lastHitAt;
@property (nonatomic, assign) uint32_t lastThreadId;

/// 是否已经真正下到硬件上（停止调试或下点失败时为 NO）
@property (nonatomic, assign) BOOL armed;
@property (nonatomic, strong, nullable) NSError *armError;

/// 用户自定义名称；为空时显示符号
@property (nonatomic, copy, nullable) NSString *label;

@property (nonatomic, strong) NSMutableArray<AccessHit *> *history;
@end

NS_ASSUME_NONNULL_END
