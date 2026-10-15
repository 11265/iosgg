#import <Foundation/Foundation.h>
#import "Constants/NotificationNames.h"

typedef NS_ENUM(NSUInteger, SSBreakpointType) {
    SSBreakpointTypeWrite,
    SSBreakpointTypeRead,
    SSBreakpointTypeReadWrite,
    SSBreakpointTypeExecute
};

typedef void (^SSBreakpointCallback)(void *address, SSBreakpointType type, uint64_t value, uint64_t instructionAddr);

@interface SSDebugger : NSObject

@property (nonatomic, assign, readonly) BOOL isDebugging;
@property (nonatomic, strong, readonly) dispatch_queue_t debugQueue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, NSDictionary<NSString *, NSNumber *> *> *instructionRegisters;
@property (nonatomic, strong, readonly) NSArray<NSString *> *lastCallStack;
@property (nonatomic, strong, readonly) NSDictionary<NSString *, id> *lastBreakpointInfo;

+ (instancetype)sharedInstance;

- (BOOL)startDebugWithPid:(pid_t)pid;
- (void)stopDebug;

- (uint64_t)readMemoryAtAddress:(uint64_t)address size:(size_t)size error:(NSError **)error;

- (BOOL)watchAddress:(uint64_t)address 
               size:(size_t)size 
               type:(SSBreakpointType)type
           callback:(SSBreakpointCallback)callback 
             error:(NSError **)error;

- (void)removeWatchAtAddress:(uint64_t)address;

- (SSBreakpointType)watchTypeForAddress:(uint64_t)address;

- (NSDictionary<NSString *, NSNumber *> *)getRegistersAtInstructionAddress:(uint64_t)address;

- (NSDictionary<NSNumber *, NSNumber *> *)getAllWatchedAddresses;

#pragma mark - Call Stack

/// 按线程端口即时抓取调用栈（元素为 @"0x..." 十六进制字符串，frame 0 = 当前 PC）。
/// 线程处于 break state（已被挂起）时结果最准确，运行态下只能拿到瞬时快照。
- (NSArray<NSString *> *)captureCallStackForThread:(uint64_t)threadId;

#pragma mark - DynaDbg Extended APIs

- (BOOL)setHardwareBreakpoint:(uint64_t)address hitCount:(int)hitCount;
- (void)removeHardwareBreakpoint:(uint64_t)address;

- (BOOL)setSoftwareBreakpoint:(uint64_t)address hitCount:(int)hitCount;
- (void)removeSoftwareBreakpoint:(uint64_t)address;

- (BOOL)enableTraceFileOutput:(NSString *)filepath;
- (void)disableTraceFileOutput;
- (uint32_t)traceFileEntryCount;

- (BOOL)continueExecution:(uint64_t)threadId;
- (BOOL)singleStep:(uint64_t)threadId;

- (BOOL)readRegister:(uint64_t)threadId name:(NSString *)name value:(uint64_t *)value;
- (BOOL)writeRegister:(uint64_t)threadId name:(NSString *)name value:(uint64_t)value;

- (BOOL)isInBreakState;

#pragma mark - Function (Execute) Breakpoints

/// 命中时是否暂停出错线程（默认 YES）。
/// NO = 只发通知并自动继续，适合每帧都会被调用的高频函数（只做调用收集，不冻结游戏）。
@property (nonatomic, assign) BOOL breakpointStopsExecution;

/// 在函数入口下执行断点。
/// software=YES：写 BRK 补丁 —— 全局生效、数量几乎无限、可升级成 inline hook，但需要代码页可写；
/// software=NO ：硬件执行断点 —— 不改内存，但硬件槽位只有 4 个左右，且之后新建的线程不会继承。
- (BOOL)setFunctionBreakpoint:(uint64_t)address software:(BOOL)software hitCount:(int)hitCount;

/// 移除执行断点（原生侧会自行判断是软件还是硬件断点）
- (void)removeFunctionBreakpoint:(uint64_t)address;

/// 该地址是否已登记执行断点（UI 用来决定菜单显示"设断点"还是"移除断点"）
- (BOOL)hasFunctionBreakpointAtAddress:(uint64_t)address;

/// 当前所有执行断点（每项含 address / software / hitCount / targetHitCount）
- (NSArray<NSDictionary<NSString *, id> *> *)functionBreakpoints;

/// 继续执行被断点停住的线程（软件断点会自动"单步越过再补回 BRK"）
- (BOOL)continueStoppedThread;

#pragma mark - Exception Queue APIs

- (NSArray<NSDictionary *> *)pollExceptions:(int)timeoutMs;
- (void)clearExceptionQueue;
- (NSInteger)exceptionQueueSize;
- (void)setExceptionCallback:(void (^)(NSDictionary *exception))callback;

@end
