#import "Modules/Debugger/SSDebugger.h"
#import "Services/LogService.h"
#import "DynaDbg/debugger/debugger.h"
#import "DynaDbg/debugger/exception_queue.h"
#import <pthread.h>

@interface SSDebugger() {
    pthread_mutex_t _debugMutex;
    pthread_mutex_t _breakpointMutex;
    pid_t _currentPid;
}

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SSBreakpointCallback> *watchCallbacks;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *watchSizes;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *watchTypes;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *addressToDebugReg;
@property (nonatomic, strong, readwrite) NSArray<NSString *> *lastCallStack;

/// 执行断点表：address -> {software, targetHitCount, hitCount}
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableDictionary<NSString *, id> *> *functionBreakpointTable;

/// 取某个观察点注册的回调（在主队列上调用）
- (SSBreakpointCallback)watchCallbackForAddress:(uint64_t)address;

/// 异常线程调用（出错线程冻结窗口内）：登记一次命中，返回"是否应暂停出错线程"
- (BOOL)registerBreakpointHitAtAddress:(uint64_t)address
                              software:(BOOL *)outSoftware
                              hitCount:(int *)outHitCount
                        targetHitCount:(int *)outTargetHitCount;

@end


extern "C" mach_port_t get_cached_task_port(pid_t pid);

#pragma mark - Call Stack Buffer

/// 异常处理线程内使用的调用栈原始缓冲：纯 C 结构，避免在"出错线程被冻结"的
/// 窗口里做内存分配（faulting thread 可能正持有 malloc 锁）
typedef struct {
    uint64_t addresses[64];
    int count;
} SSRawCallStack;


/// 原始帧 -> 十六进制字符串数组（与 AccessRegisterViewController、AccessViewModel 的约定一致）。
/// 会分配内存，因此只在主队列里调用，不要在"出错线程冻结窗口"内调用。
static NSArray<NSString *> *SSCallStackToArray(SSRawCallStack stack) {
    if (stack.count <= 0) {
        return @[];
    }
    NSMutableArray<NSString *> *callStack =
        [NSMutableArray arrayWithCapacity:(NSUInteger)stack.count];
    for (int i = 0; i < stack.count; i++) {
        [callStack addObject:[NSString stringWithFormat:@"0x%llX", stack.addresses[i]]];
    }
    return [callStack copy];
}

#pragma mark - Native Log & Exception Info Callbacks

extern "C" void native_log(int level, const char *message) {
    NSString *msg = [NSString stringWithUTF8String:message];
    switch (level) {
        case 1:
            [LoggingService log:@"[ERROR] %@", msg];
            break;
        case 2:
            [LoggingService log:@"[WARN] %@", msg];
            break;
        case 3:
            [LoggingService log:@"[INFO] %@", msg];
            break;
        case 4:
            [LoggingService log:@"[DEBUG] %@", msg];
            break;
        case 5:
            [LoggingService log:@"[TRACE] %@", msg];
            break;
        default:
            [LoggingService log:@"%@", msg];
            break;
    }
}

extern "C" bool send_exception_info(const NativeExceptionInfo* info, pid_t pid) {
    // 返回值语义：true = 让出错线程停在断点（break state），false = 立即自动继续
    if (info->architecture != ARCH_ARM64) {
        return true;
    }

    uint64_t watchpoint_address = info->watchpoint_address;
    uint64_t watchpoint_size = info->watchpoint_size;
    uint64_t memory_address = info->memory_address;
    uint64_t pc = info->regs.arm64.pc;
    uint64_t thread_id = info->thread_id;
    uint64_t exception_type = info->exception_type;

    [LoggingService log:@"[异常] 类型=%llu, 线程=%llu, PC=0x%llX, MemAddr=0x%llX, WPAddr=0x%llX",
            exception_type, thread_id, pc, memory_address, watchpoint_address];

    // ---- 寄存器快照（各类异常共用）----
    NSMutableDictionary *registers = [NSMutableDictionary dictionary];
    for (int i = 0; i < 30; i++) {
        registers[[NSString stringWithFormat:@"x%d", i]] = @(info->regs.arm64.x[i]);
    }
    registers[@"lr"] = @(info->regs.arm64.lr);
    registers[@"sp"] = @(info->regs.arm64.sp);
    registers[@"pc"] = @(info->regs.arm64.pc);
    registers[@"cpsr"] = @(info->regs.arm64.cpsr);
    registers[@"fp"] = @(info->regs.arm64.fp);

    // ---- 调用栈：必须在异常线程被内核冻结的窗口内同步抓取 ----
    // （dispatch_async 之后再读就晚了：那会儿出错线程可能已经恢复，栈内容就变了）
    // 展开是纯 C 实现（无 malloc / 无 ObjC），trace 模式的异常频率极高，直接跳过。
    SSRawCallStack rawCallStack = {};
    if (info->is_trace == 0) {
        mach_port_t stack_task = get_cached_task_port(pid);
        if (stack_task != MACH_PORT_NULL) {
            rawCallStack.count =
                unwind_fp_chain(stack_task,
                                pc,
                                info->regs.arm64.fp,
                                info->regs.arm64.sp,
                                info->regs.arm64.lr,
                                rawCallStack.addresses,
                                (int)(sizeof(rawCallStack.addresses) /
                                      sizeof(rawCallStack.addresses[0])));
        }
    }

    // trace 模式（硬件断点跟踪）有自己的单步通道：不打扰 UI，也不改变原有暂停行为
    if (info->is_trace != 0) {
        return true;
    }

    if (exception_type == EXCEPTION_WATCHPOINT) {
        // 读一次被监视内存的当前值，供访问记录展示
        uint64_t value = 0;
        mach_port_t task = get_cached_task_port(pid);
        if (task != MACH_PORT_NULL) {
            mach_vm_size_t outsize = sizeof(uint64_t);
            kern_return_t kr = mach_vm_read_overwrite(task,
                                                      memory_address,
                                                      sizeof(uint64_t),
                                                      (mach_vm_address_t)&value,
                                                      &outsize);
            if (kr == KERN_SUCCESS) {
                if (watchpoint_size == 1) {
                    value = value & 0xFF;
                } else if (watchpoint_size == 2) {
                    value = value & 0xFFFF;
                } else if (watchpoint_size == 4) {
                    value = value & 0xFFFFFFFF;
                }
            } else {
                [LoggingService log:@"[异常] 读取内存值失败: kr=%d, addr=0x%llX", kr, memory_address];
            }
        } else {
            [LoggingService log:@"[异常] 无法获取 task port for pid=%d", pid];
        }

        SSBreakpointType type = [[SSDebugger sharedInstance] watchTypeForAddress:watchpoint_address];
        SSBreakpointCallback callback =
            [[SSDebugger sharedInstance] watchCallbackForAddress:watchpoint_address];

        dispatch_async(dispatch_get_main_queue(), ^{
            // 回调是 watchAddress:...callback: 承诺的语义，原先只存不调（TracePage 的列表因此是死的）
            if (callback) {
                callback((void *)watchpoint_address, type, value, pc);
            }

            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[@"address"] = @(watchpoint_address);
            userInfo[@"pc"] = @(pc);
            userInfo[@"threadId"] = @(thread_id);
            userInfo[@"exceptionType"] = @(exception_type);
            userInfo[@"registers"] = registers;
            userInfo[@"memoryAddress"] = @(memory_address);
            userInfo[@"value"] = @(value);
            userInfo[@"type"] = @(type);

            NSArray<NSString *> *callStack = SSCallStackToArray(rawCallStack);
            userInfo[@"callStack"] = callStack;
            if (callStack.count > 0) {
                [SSDebugger sharedInstance].lastCallStack = callStack;
                [LoggingService log:@"[异常] 调用栈 %d 帧: frame0=%@, frame1=%@",
                        (int)callStack.count,
                        callStack[0],
                        callStack.count > 1 ? callStack[1] : @"-"];
            }

            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSSDebuggerDidHitWatchpointNotification
                object:[SSDebugger sharedInstance]
                userInfo:userInfo];
        });

        // 观察点由 handle_watchpoint_hit 负责单步越过并重新武装，这里不需要暂停线程
        return true;
    }

    if (exception_type == EXCEPTION_BREAKPOINT) {
        // 执行断点命中：PC 就是断点地址（软件 BRK 与硬件执行断点都一样）
        BOOL isSoftware = NO;
        int hitCount = 0;
        int targetHitCount = 0;
        BOOL shouldStop = [[SSDebugger sharedInstance] registerBreakpointHitAtAddress:pc
                                                                            software:&isSoftware
                                                                            hitCount:&hitCount
                                                                      targetHitCount:&targetHitCount];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<NSString *> *callStack = SSCallStackToArray(rawCallStack);

            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[@"address"] = @(pc);
            userInfo[@"pc"] = @(pc);
            userInfo[@"threadId"] = @(thread_id);
            userInfo[@"exceptionType"] = @(exception_type);
            userInfo[@"registers"] = registers;
            userInfo[@"callStack"] = callStack;
            userInfo[@"stopExecution"] = @(shouldStop);
            userInfo[@"breakpoint"] = @{
                @"address": @(pc),
                @"software": @(isSoftware),
                @"hitCount": @(hitCount),
                @"targetHitCount": @(targetHitCount)
            };

            if (callStack.count > 0) {
                [SSDebugger sharedInstance].lastCallStack = callStack;
            }

            [LoggingService log:@"[断点] 命中 0x%llX（%@），调用栈 %d 帧: frame0=%@, frame1=%@，%@",
                    pc,
                    isSoftware ? @"软件" : @"硬件",
                    (int)callStack.count,
                    callStack.count > 0 ? callStack[0] : @"-",
                    callStack.count > 1 ? callStack[1] : @"-",
                    shouldStop ? @"线程已暂停" : @"自动继续"];

            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSSDebuggerDidHitBreakpointNotification
                object:[SSDebugger sharedInstance]
                userInfo:userInfo];
        });

        return shouldStop;
    }

    // 单步等其它类型：只记日志、不发通知（避免污染"访问记录"里出现地址 0 的假记录）
    return true;
}

#pragma mark - DynaDbg Implementation Files

#include "DynaDbg/debugger/debugger_native_api.mm"
#include "DynaDbg/debugger/debugger_core.mm"
#include "DynaDbg/debugger/debugger_watchpoint.mm"
#include "DynaDbg/debugger/debugger_breakpoint.mm"
#include "DynaDbg/debugger/debugger_exception.mm"
#include "DynaDbg/debugger/debugger_trace.mm"
#include "DynaDbg/debugger/debugger_register.mm"
#include "DynaDbg/debugger/debugger_unwind.mm"
#include "DynaDbg/core/native_api.mm"
#include "DynaDbg/core/process_api.mm"
#include "DynaDbg/core/file_api.mm"
#include "DynaDbg/common/util.cpp"
#include "DynaDbg/common/trace_file.cpp"
#include "DynaDbg/common/arm64_decoder.cpp"

@implementation SSDebugger

+ (instancetype)sharedInstance {
    static SSDebugger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSDebugger alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _watchCallbacks = [NSMutableDictionary dictionary];
        _watchSizes = [NSMutableDictionary dictionary];
        _watchTypes = [NSMutableDictionary dictionary];
        _addressToDebugReg = [NSMutableDictionary dictionary];
        _functionBreakpointTable = [NSMutableDictionary dictionary];
        _breakpointStopsExecution = YES;
        _debugQueue = dispatch_queue_create("com.ss.debugger", DISPATCH_QUEUE_SERIAL);
        _currentPid = -1;
        _isDebugging = NO;
        pthread_mutex_init(&_debugMutex, NULL);
        pthread_mutex_init(&_breakpointMutex, NULL);
        
        native_init(1);
    }
    return self;
}

- (void)dealloc {
    pthread_mutex_destroy(&_debugMutex);
    pthread_mutex_destroy(&_breakpointMutex);
}

- (BOOL)startDebugWithPid:(pid_t)pid {
    pthread_mutex_lock(&_debugMutex);
    if (_isDebugging) {
        pthread_mutex_unlock(&_debugMutex);
        return NO;
    }
    
    _currentPid = pid;
    
    if (!debugger_new(pid)) {
        [LoggingService log:@"DynaDbg debugger_new 失败 (PID: %d)", pid];
        pthread_mutex_unlock(&_debugMutex);
        return NO;
    }
    
    _isDebugging = YES;
    pthread_mutex_unlock(&_debugMutex);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSSDebuggerStateChangedNotification object:self];
    });
    
    [LoggingService log:@"DynaDbg 调试器已启动 (PID: %d)", pid];
    return YES;
}

- (void)stopDebug {
    pthread_mutex_lock(&_debugMutex);
    if (!_isDebugging) {
        pthread_mutex_unlock(&_debugMutex);
        return;
    }
    
    if (g_debugger) {
        delete g_debugger;
        g_debugger = nullptr;
    }
    
    _isDebugging = NO;
    _currentPid = -1;
    
    [self.watchCallbacks removeAllObjects];
    [self.watchSizes removeAllObjects];
    [self.watchTypes removeAllObjects];
    [self.addressToDebugReg removeAllObjects];
    
    pthread_mutex_unlock(&_debugMutex);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSSDebuggerStateChangedNotification object:self];
    });
    
    [LoggingService log:@"DynaDbg 调试器已停止"];
}

- (uint64_t)readMemoryAtAddress:(uint64_t)address size:(size_t)size error:(NSError **)error {
    unsigned char *buffer = (unsigned char *)malloc(size);
    if (!buffer) {
        if (error) {
            *error = [NSError errorWithDomain:@"SSDebugger" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"内存分配失败"}];
        }
        return 0;
    }
    
    ssize_t bytesRead = read_memory_native(_currentPid, address, size, buffer);
    if (bytesRead <= 0) {
        free(buffer);
        if (error) {
            *error = [NSError errorWithDomain:@"SSDebugger" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"读取内存失败"}];
        }
        return 0;
    }
    
    uint64_t value = 0;
    memcpy(&value, buffer, MIN(size, sizeof(uint64_t)));
    free(buffer);
    
    return value;
}

- (BOOL)watchAddress:(uint64_t)address 
               size:(size_t)size 
               type:(SSBreakpointType)type
           callback:(SSBreakpointCallback)callback 
             error:(NSError **)error {
    
    [LoggingService log:@"[watchAddress] 开始设置观察点: 地址=0x%llX, 大小=%zu, 类型=%ld", address, size, (long)type];
    
    WatchpointType wpType;
    switch (type) {
        case SSBreakpointTypeRead:
            wpType = WatchpointType::READ;
            break;
        case SSBreakpointTypeWrite:
            wpType = WatchpointType::WRITE;
            break;
        case SSBreakpointTypeReadWrite:
            wpType = WatchpointType::READWRITE;
            break;
        default:
            wpType = WatchpointType::WRITE;
            break;
    }
    
    kern_return_t kr = set_watchpoint_native(address, (int)size, wpType);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"SSDebugger" code:kr userInfo:@{NSLocalizedDescriptionKey: @"设置观察点失败"}];
        }
        [LoggingService log:@"设置观察点失败: 0x%llX, kr=%d", address, kr];
        return NO;
    }
    
    NSNumber *addrNum = @(address);
    if (callback) {
        self.watchCallbacks[addrNum] = callback;
    }
    self.watchSizes[addrNum] = @(size);
    self.watchTypes[addrNum] = @(type);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *userInfo = @{
            @"address": @(address),
            @"type": @(type)
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:kSSDebuggerDidAddWatchpointNotification 
                                                            object:self 
                                                          userInfo:userInfo];
    });
    
    [LoggingService log:@"观察点已设置: 0x%llX, 大小=%zu, 类型=%ld", address, size, (long)type];
    return YES;
}

- (void)removeWatchAtAddress:(uint64_t)address {
    kern_return_t kr = remove_watchpoint_native(address);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"移除观察点失败: 0x%llX, kr=%d", address, kr];
        return;
    }
    
    NSNumber *addrNum = @(address);
    [self.watchCallbacks removeObjectForKey:addrNum];
    [self.watchSizes removeObjectForKey:addrNum];
    [self.watchTypes removeObjectForKey:addrNum];
    [self.addressToDebugReg removeObjectForKey:addrNum];
    
    [LoggingService log:@"观察点已移除: 0x%llX", address];
}

- (SSBreakpointCallback)watchCallbackForAddress:(uint64_t)address {
    @synchronized (self.watchCallbacks) {
        return self.watchCallbacks[@(address)];
    }
}

- (SSBreakpointType)watchTypeForAddress:(uint64_t)address {
    NSNumber *addrNum = @(address);
    NSNumber *type = self.watchTypes[addrNum];
    if (type) {
        [LoggingService log:@"[watchTypeForAddress] 找到类型: 地址=0x%llX, 类型=%ld", address, (long)[type intValue]];
        return (SSBreakpointType)[type intValue];
    }
    [LoggingService log:@"[watchTypeForAddress] 未找到类型: 地址=0x%llX, 已注册地址数: %lu", address, (unsigned long)self.watchTypes.count];
    for (NSNumber *key in self.watchTypes) {
        [LoggingService log:@"[watchTypeForAddress] 已注册: 0x%llx -> %ld", [key unsignedLongLongValue], (long)[self.watchTypes[key] intValue]];
    }
    return SSBreakpointTypeReadWrite;
}

- (NSDictionary<NSString *, NSNumber *> *)getRegistersAtInstructionAddress:(uint64_t)address {
    return self.instructionRegisters[@(address)] ?: @{};
}

- (NSDictionary<NSNumber *, NSNumber *> *)getAllWatchedAddresses {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSNumber *addr in self.watchTypes) {
        result[addr] = self.watchTypes[addr];
    }
    return [result copy];
}

#pragma mark - Call Stack

- (NSArray<NSString *> *)captureCallStackForThread:(uint64_t)threadId {
    if (threadId == 0 || !_isDebugging) {
        return @[];
    }
    
    mach_port_t task = get_cached_task_port(_currentPid);
    if (task == MACH_PORT_NULL) {
        return @[];
    }
    
    uint64_t frames[64] = {0};
    int frame_count = get_call_stack_for_thread_native(
        task, (mach_port_t)threadId, frames, (int)(sizeof(frames) / sizeof(frames[0])));
    if (frame_count <= 0) {
        return @[];
    }
    
    NSMutableArray<NSString *> *callStack =
        [NSMutableArray arrayWithCapacity:(NSUInteger)frame_count];
    for (int i = 0; i < frame_count; i++) {
        [callStack addObject:[NSString stringWithFormat:@"0x%llX", frames[i]]];
    }
    
    [LoggingService log:@"[调用栈] 线程 %llu 抓取到 %d 帧", threadId, frame_count];
    return [callStack copy];
}

#pragma mark - Function (Execute) Breakpoints

- (BOOL)setFunctionBreakpoint:(uint64_t)address software:(BOOL)software hitCount:(int)hitCount {
    if (address == 0) {
        [LoggingService log:@"[断点] 地址为 0，拒绝下断点"];
        return NO;
    }

    BOOL ok = software ? [self setSoftwareBreakpoint:address hitCount:hitCount]
                       : [self setHardwareBreakpoint:address hitCount:hitCount];
    if (!ok) {
        return NO;
    }

    pthread_mutex_lock(&_breakpointMutex);
    NSMutableDictionary<NSString *, id> *meta = [NSMutableDictionary dictionary];
    meta[@"address"] = @(address);
    meta[@"software"] = @(software);
    meta[@"targetHitCount"] = @(hitCount);
    meta[@"hitCount"] = @0;
    self.functionBreakpointTable[@(address)] = meta;
    pthread_mutex_unlock(&_breakpointMutex);

    [LoggingService log:@"[断点] 已设置%@执行断点: 0x%llX（命中后%@）",
            software ? @"软件" : @"硬件",
            address,
            self.breakpointStopsExecution ? @"暂停并弹出寄存器+调用栈" : @"不暂停，仅通知"];
    return YES;
}

- (void)removeFunctionBreakpoint:(uint64_t)address {
    pthread_mutex_lock(&_breakpointMutex);
    BOOL existed = (self.functionBreakpointTable[@(address)] != nil);
    [self.functionBreakpointTable removeObjectForKey:@(address)];
    pthread_mutex_unlock(&_breakpointMutex);

    if (!existed) {
        [LoggingService log:@"[断点] 该地址没有登记的执行断点: 0x%llX", address];
    }

    // 原生 remove_breakpoint 会自行判断该地址是软件断点还是硬件断点
    kern_return_t kr = remove_breakpoint_native(address);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[断点] 移除执行断点失败: 0x%llX, kr=%d", address, kr];
        return;
    }
    [LoggingService log:@"[断点] 已移除执行断点: 0x%llX", address];
}

- (BOOL)hasFunctionBreakpointAtAddress:(uint64_t)address {
    pthread_mutex_lock(&_breakpointMutex);
    BOOL exists = (self.functionBreakpointTable[@(address)] != nil);
    pthread_mutex_unlock(&_breakpointMutex);
    return exists;
}

- (NSArray<NSDictionary<NSString *, id> *> *)functionBreakpoints {
    pthread_mutex_lock(&_breakpointMutex);
    NSMutableArray<NSDictionary<NSString *, id> *> *result =
        [NSMutableArray arrayWithCapacity:self.functionBreakpointTable.count];
    for (NSNumber *key in self.functionBreakpointTable) {
        [result addObject:[self.functionBreakpointTable[key] copy]];
    }
    pthread_mutex_unlock(&_breakpointMutex);
    return [result copy];
}

- (BOOL)registerBreakpointHitAtAddress:(uint64_t)address
                              software:(BOOL *)outSoftware
                              hitCount:(int *)outHitCount
                        targetHitCount:(int *)outTargetHitCount {
    // 在异常线程（出错线程冻结窗口）里调用：只做查表 + 自增，不分配大对象
    BOOL shouldStop = _breakpointStopsExecution;

    pthread_mutex_lock(&_breakpointMutex);
    NSMutableDictionary<NSString *, id> *meta = self.functionBreakpointTable[@(address)];
    if (meta) {
        int hits = [meta[@"hitCount"] intValue] + 1;
        meta[@"hitCount"] = @(hits);
        if (outSoftware) *outSoftware = [meta[@"software"] boolValue];
        if (outHitCount) *outHitCount = hits;
        if (outTargetHitCount) *outTargetHitCount = [meta[@"targetHitCount"] intValue];
    } else {
        if (outSoftware) *outSoftware = NO;
        if (outHitCount) *outHitCount = 0;
        if (outTargetHitCount) *outTargetHitCount = 0;
    }
    pthread_mutex_unlock(&_breakpointMutex);

    return shouldStop;
}

- (BOOL)continueStoppedThread {
    kern_return_t kr = continue_last_stopped_thread_native();
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[断点] 继续执行失败: kr=%d（可能当前没有停顿中的线程）", kr];
        return NO;
    }
    [LoggingService log:@"[断点] 已继续执行被断住的线程"];
    return YES;
}

#pragma mark - DynaDbg Extended APIs

- (BOOL)setHardwareBreakpoint:(uint64_t)address hitCount:(int)hitCount {
    kern_return_t kr = set_breakpoint_native(address, hitCount, false, 0);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"设置硬件断点失败: 0x%llX, kr=%d", address, kr];
        return NO;
    }
    [LoggingService log:@"硬件断点已设置: 0x%llX, hitCount=%d", address, hitCount];
    return YES;
}

- (void)removeHardwareBreakpoint:(uint64_t)address {
    kern_return_t kr = remove_breakpoint_native(address);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"移除硬件断点失败: 0x%llX, kr=%d", address, kr];
    }
}

- (BOOL)setSoftwareBreakpoint:(uint64_t)address hitCount:(int)hitCount {
    kern_return_t kr = set_breakpoint_native(address, hitCount, true, 0);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"设置软件断点失败: 0x%llX, kr=%d", address, kr];
        return NO;
    }
    [LoggingService log:@"软件断点已设置: 0x%llX, hitCount=%d", address, hitCount];
    return YES;
}

- (void)removeSoftwareBreakpoint:(uint64_t)address {
    kern_return_t kr = remove_breakpoint_native(address);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"移除断点失败: 0x%llX, kr=%d", address, kr];
    }
}

- (BOOL)enableTraceFileOutput:(NSString *)filepath {
    enable_trace_file_output_native(filepath.UTF8String);
    return is_trace_file_output_enabled_native();
}

- (void)disableTraceFileOutput {
    disable_trace_file_output_native();
}

- (uint32_t)traceFileEntryCount {
    return get_trace_file_entry_count_native();
}

- (BOOL)continueExecution:(uint64_t)threadId {
    kern_return_t kr = continue_execution_native((mach_port_t)threadId);
    return kr == KERN_SUCCESS;
}

- (BOOL)singleStep:(uint64_t)threadId {
    kern_return_t kr = single_step_native((mach_port_t)threadId);
    return kr == KERN_SUCCESS;
}

- (BOOL)readRegister:(uint64_t)threadId name:(NSString *)name value:(uint64_t *)value {
    if (!value) return NO;
    kern_return_t kr = read_register_native((mach_port_t)threadId, name.UTF8String, value);
    return kr == KERN_SUCCESS;
}

- (BOOL)writeRegister:(uint64_t)threadId name:(NSString *)name value:(uint64_t)value {
    kern_return_t kr = write_register_native((mach_port_t)threadId, name.UTF8String, value);
    return kr == KERN_SUCCESS;
}

- (BOOL)isInBreakState {
    return is_in_break_state_native();
}

#pragma mark - Exception Queue APIs

- (NSArray<NSDictionary *> *)pollExceptions:(int)timeoutMs {
    char *jsonStr = exception_queue_pop_all_json(timeoutMs);
    if (!jsonStr) {
        return @[];
    }
    
    NSString *jsonNSString = [NSString stringWithUTF8String:jsonStr];
    exception_queue_free_string(jsonStr);
    
    if (!jsonNSString) {
        return @[];
    }
    
    NSData *data = [jsonNSString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    
    if (error || !json || ![json isKindOfClass:[NSDictionary class]]) {
        return @[];
    }
    
    NSArray *exceptions = json[@"exceptions"];
    if (!exceptions || ![exceptions isKindOfClass:[NSArray class]]) {
        return @[];
    }
    
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:exceptions.count];
    for (id exc in exceptions) {
        if ([exc isKindOfClass:[NSDictionary class]]) {
            [result addObject:exc];
        }
    }
    
    return [result copy];
}

- (void)clearExceptionQueue {
    exception_queue_clear();
}

- (NSInteger)exceptionQueueSize {
    return exception_queue_size();
}

- (void)setExceptionCallback:(void (^)(NSDictionary *exception))callback {
    ExceptionQueue::instance().setCallback([callback](const ExceptionInfo& info) {
        if (!callback) return;
        
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"type"] = @(info.type);
        dict[@"thread_id"] = @(info.thread_id);
        dict[@"pc_address"] = @(info.pc_address);
        dict[@"memory_address"] = @(info.memory_address);
        dict[@"watchpoint_index"] = @(info.watchpoint_index);
        dict[@"breakpoint_index"] = @(info.breakpoint_index);
        dict[@"single_step_mode"] = @(static_cast<int>(info.single_step_mode));
        dict[@"is_trace"] = @(info.is_trace);
        dict[@"timestamp"] = [NSString stringWithUTF8String:info.timestamp.c_str()];
        
        NSMutableDictionary *regs = [NSMutableDictionary dictionary];
        for (int i = 0; i < 30; i++) {
            regs[[NSString stringWithFormat:@"x%d", i]] = @(info.registers.x[i]);
        }
        regs[@"lr"] = @(info.registers.lr);
        regs[@"sp"] = @(info.registers.sp);
        regs[@"pc"] = @(info.registers.pc);
        regs[@"cpsr"] = @(info.registers.cpsr);
        regs[@"fp"] = @(info.registers.fp);
        dict[@"registers"] = regs;
        
        if (!info.instruction.empty()) {
            dict[@"instruction"] = [NSString stringWithUTF8String:info.instruction.c_str()];
        }
        
        callback(dict);
    });
}

@end
