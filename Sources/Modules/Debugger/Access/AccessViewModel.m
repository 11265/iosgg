#import "Modules/Debugger/Access/AccessViewModel.h"
#import "Modules/Debugger/Access/AccessRecord.h"
#import "Services/LogService.h"

#import <unistd.h>

NSNotificationName const AccessViewModelDidUpdateNotification = @"AccessViewModelDidUpdateNotification";
NSNotificationName const AccessViewModelDebugStateChangedNotification = @"AccessViewModelDebugStateChangedNotification";

static const NSInteger kMaxHistoryCount = 50;
static const NSTimeInterval kNotifyDebounceInterval = 0.1;

static NSError *SSAccessError(NSString *message) {
    return [NSError errorWithDomain:@"SSAccess"
                               code:-1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"访问点操作失败"}];
}

@interface AccessViewModel ()

@property (nonatomic, strong) NSMutableArray<AccessRecord *> *mutableRecords;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *watchAddresses;
@property (nonatomic, readwrite) BOOL isDebugging;
@property (nonatomic, assign) BOOL hasPendingUpdate;
@property (nonatomic, strong) dispatch_block_t pendingNotifyBlock;

@end

@implementation AccessViewModel

- (instancetype)init {
    if (self = [super init]) {
        _mutableRecords = [NSMutableArray array];
        _watchAddresses = [NSMutableArray array];
        [self setupNotifications];
        [self syncWithDebugger];
    }
    return self;
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWatchpointHit:)
                                                 name:kSSDebuggerDidHitWatchpointNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWatchpointAdded:)
                                                 name:kSSDebuggerDidAddWatchpointNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDebuggerStateChanged:)
                                                 name:kSSDebuggerStateChangedNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray<AccessRecord *> *)records {
    return [_mutableRecords copy];
}

- (NSUInteger)watchpointCount {
    return _mutableRecords.count;
}

- (NSUInteger)slotLimit {
    return 4;
}

#pragma mark - Watchpoint Management

- (BOOL)addWatchpoint:(uint64_t)address
                 type:(SSBreakpointType)type
                error:(NSError * _Nullable * _Nullable)error {
    [LoggingService log:@"AccessViewModel: addWatchpoint 地址=0x%llx 类型=%d", address, type];

    if (address == 0) {
        if (error) *error = SSAccessError(@"地址不能为 0");
        return NO;
    }

    // 同一地址再次添加：视为“切换类型/重新启用”，而不是报重复
    AccessRecord *existing = [self recordForAddress:address];
    if (existing) {
        if (![self ensureDebuggerRunning:error]) {
            return NO;
        }
        if (existing.type != type && ![self setType:type forAddress:address error:error]) {
            return NO;
        }
        if (!existing.enabled) {
            if (![self setEnabled:YES forAddress:address error:error]) {
                return NO;
            }
        } else if (!existing.armed) {
            if (![self armRecord:existing error:error]) {
                return NO;
            }
            [self notifyUpdate];
        }
        [LoggingService log:@"AccessViewModel: 地址已存在，已切换为类型 %d", (int)type];
        return YES;
    }

    if (_mutableRecords.count >= self.slotLimit) {
        if (error) *error = SSAccessError(@"硬件槽已满（4/4），请先删除或合并一个访问点");
        return NO;
    }
    if ([self addressExists:address]) {
        if (error) *error = SSAccessError(@"该地址已经在监视中");
        return NO;
    }

    NSDictionary<NSNumber *, NSNumber *> *watched = [[SSDebugger sharedInstance] getAllWatchedAddresses];
    if (watched[@(address)] != nil) {
        if (error) *error = SSAccessError(@"该地址已被其它页面监视（可能来自 TracePage）");
        return NO;
    }

    if (![self ensureDebuggerRunning:error]) {
        return NO;
    }

    AccessRecord *record = [[AccessRecord alloc] init];
    record.address = address;
    record.type = type;
    record.enabled = YES;
    record.timestamp = [NSDate date];

    if (![self armRecord:record error:error]) {
        return NO;
    }

    [_watchAddresses addObject:@(address)];
    [_mutableRecords addObject:record];

    [LoggingService log:@"AccessViewModel: 成功添加记录，当前记录数=%lu", (unsigned long)_mutableRecords.count];
    [self notifyUpdate];
    return YES;
}

- (void)addWatchpoint:(uint64_t)address type:(SSBreakpointType)type {
    NSError *error = nil;
    if (![self addWatchpoint:address type:type error:&error]) {
        [LoggingService log:@"AccessViewModel: 添加失败: %@", error.localizedDescription];
    }
}

- (void)removeWatchpointAtIndex:(NSUInteger)index {
    if (index >= _mutableRecords.count) return;

    AccessRecord *record = _mutableRecords[index];
    uint64_t address = record.address;

    [[SSDebugger sharedInstance] removeWatchAtAddress:address];
    record.armed = NO;
    record.armError = nil;

    [_watchAddresses removeObject:@(address)];
    [_mutableRecords removeObjectAtIndex:index];

    [self notifyUpdate];
}

- (void)removeAllWatchpoints {
    for (AccessRecord *record in _mutableRecords) {
        [[SSDebugger sharedInstance] removeWatchAtAddress:record.address];
        record.armed = NO;
        record.armError = nil;
    }

    [_watchAddresses removeAllObjects];
    [_mutableRecords removeAllObjects];

    [self notifyUpdate];
}

- (BOOL)setEnabled:(BOOL)enabled forAddress:(uint64_t)address error:(NSError * _Nullable * _Nullable)error {
    AccessRecord *record = [self recordForAddress:address];
    if (!record) {
        if (error) *error = SSAccessError(@"访问点不存在");
        return NO;
    }
    if (record.enabled == enabled) {
        return YES;
    }

    if (!enabled) {
        [[SSDebugger sharedInstance] removeWatchAtAddress:address];
        record.enabled = NO;
        record.armed = NO;
        record.armError = nil;
        [self notifyUpdate];
        return YES;
    }

    if (![self ensureDebuggerRunning:error]) {
        return NO;
    }

    if (![self armRecord:record error:error]) {
        record.enabled = NO;
        record.armed = NO;
        [self notifyUpdate];
        return NO;
    }

    record.enabled = YES;
    record.armed = YES;
    [self notifyUpdate];
    return YES;
}

- (void)setEnabled:(BOOL)enabled forAddress:(uint64_t)address {
    NSError *error = nil;
    if (![self setEnabled:enabled forAddress:address error:&error]) {
        [LoggingService log:@"AccessViewModel: 启停失败: %@", error.localizedDescription];
    }
}

- (BOOL)setType:(SSBreakpointType)type forAddress:(uint64_t)address error:(NSError * _Nullable * _Nullable)error {
    AccessRecord *record = [self recordForAddress:address];
    if (!record) {
        if (error) *error = SSAccessError(@"访问点不存在");
        return NO;
    }
    if (record.type == type) {
        return YES;
    }

    SSBreakpointType oldType = record.type;
    record.type = type;

    if (record.enabled && [SSDebugger sharedInstance].isDebugging) {
        // 没有真正武装过时不需要摘旧点，直接按新类型下点
        if (record.armed && ![[SSDebugger sharedInstance] removeWatchAtAddress:address]) {
            record.type = oldType;
            if (error) *error = SSAccessError(@"移除旧观察点失败，类型未切换");
            [self notifyUpdate];
            return NO;
        }

        if (![self armRecord:record error:error]) {
            record.type = oldType;
            [self armRecord:record error:NULL];
            [self notifyUpdate];
            return NO;
        }
        record.armed = YES;
    } else {
        record.armed = NO;
    }

    [self notifyUpdate];
    return YES;
}

- (void)setType:(SSBreakpointType)type forAddress:(uint64_t)address {
    NSError *error = nil;
    if (![self setType:type forAddress:address error:&error]) {
        [LoggingService log:@"AccessViewModel: 切换类型失败: %@", error.localizedDescription];
    }
}

- (BOOL)addressExists:(uint64_t)address {
    for (NSNumber *addrNum in _watchAddresses) {
        if ([addrNum unsignedLongLongValue] == address) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Arm helpers

- (BOOL)ensureDebuggerRunning:(NSError * _Nullable * _Nullable)error {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    if (debugger.isDebugging) {
        return YES;
    }

    if (![debugger startDebugWithPid:getpid()]) {
        if (error) *error = SSAccessError(@"调试器启动失败");
        return NO;
    }

    // 新起的调试器没有任何观察点，强制全部重新武装
    for (AccessRecord *record in _mutableRecords) {
        if (record.enabled) {
            record.armed = NO;
        }
    }
    [self rearmAllRecords];
    return YES;
}

- (void)rearmAllRecords {
    for (AccessRecord *record in _mutableRecords) {
        if (!record.enabled) {
            record.armed = NO;
            continue;
        }
        if (record.armed) {
            continue;   // 已在硬件上，避免重复占用槽位
        }
        NSError *error = nil;
        if (![self armRecord:record error:&error]) {
            [LoggingService log:@"AccessViewModel: 重新武装失败 0x%llX: %@",
             record.address, error.localizedDescription];
        }
    }
}

- (BOOL)armRecord:(AccessRecord *)record error:(NSError * _Nullable * _Nullable)error {
    NSError *watchError = nil;
    BOOL success = [[SSDebugger sharedInstance] watchAddress:record.address
                                                        size:8
                                                        type:record.type
                                                    callback:nil
                                                      error:&watchError];
    record.armed = success;
    record.armError = success ? nil : watchError;

    if (!success && error) {
        *error = SSAccessError(watchError.localizedDescription ?: @"设置观察点失败");
    }
    return success;
}

#pragma mark - Debugging Control

- (void)startDebugging {
    SSDebugger *debugger = [SSDebugger sharedInstance];

    if (debugger.isDebugging) {
        [self rearmAllRecords];
    } else if ([debugger startDebugWithPid:getpid()]) {
        // 新调试器上还没有任何观察点
        for (AccessRecord *record in _mutableRecords) {
            if (record.enabled) {
                record.armed = NO;
            }
        }
        [self rearmAllRecords];
    } else {
        [LoggingService log:@"AccessViewModel: 调试器启动失败"];
    }

    [self notifyUpdate];
}

- (void)stopDebugging {
    [[SSDebugger sharedInstance] stopDebug];

    for (AccessRecord *record in _mutableRecords) {
        record.armed = NO;
        record.armError = nil;
    }

    [self notifyUpdate];
}

- (void)toggleDebugging {
    if (self.isDebugging) {
        [self stopDebugging];
    } else {
        [self startDebugging];
    }
}

#pragma mark - Data Access

- (AccessRecord *)recordAtIndex:(NSUInteger)index {
    if (index >= _mutableRecords.count) return nil;
    return _mutableRecords[index];
}

- (AccessRecord *)recordForAddress:(uint64_t)address {
    for (AccessRecord *record in _mutableRecords) {
        if (record.address == address) {
            return record;
        }
    }
    return nil;
}

- (NSInteger)indexOfRecord:(AccessRecord *)record {
    NSUInteger index = [_mutableRecords indexOfObjectIdenticalTo:record];
    return index == NSNotFound ? NSNotFound : (NSInteger)index;
}

- (void)resetHitCountForAddress:(uint64_t)address {
    AccessRecord *record = [self recordForAddress:address];
    if (!record) return;

    record.hitCount = 0;
    record.value = 0;
    record.hasValue = NO;
    record.instructionAddr = 0;
    record.registers = nil;
    record.callStack = nil;
    record.lastHitAt = nil;
    record.lastThreadId = 0;
    [record.history removeAllObjects];

    [self notifyUpdate];
}

- (void)syncWithDebugger {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    self.isDebugging = debugger.isDebugging;

    NSDictionary<NSNumber *, NSNumber *> *watched = [debugger getAllWatchedAddresses];

    for (NSNumber *addrNum in watched) {
        uint64_t address = addrNum.unsignedLongLongValue;
        AccessRecord *record = [self recordForAddress:address];
        if (!record) {
            record = [[AccessRecord alloc] init];
            record.address = address;
            record.type = (SSBreakpointType)[watched[addrNum] intValue];
            record.timestamp = [NSDate date];
            record.enabled = YES;
            [_watchAddresses addObject:addrNum];
            [_mutableRecords addObject:record];
        }
        record.armed = self.isDebugging;
        record.armError = nil;
    }

    for (AccessRecord *record in _mutableRecords) {
        if (watched[@(record.address)] == nil) {
            record.armed = NO;
        }
    }

    [self notifyUpdate];
}

#pragma mark - Notification Handlers

- (void)handleWatchpointHit:(NSNotification *)notification {
    [LoggingService log:@"[AccessViewModel] handleWatchpointHit 收到通知"];

    NSDictionary *userInfo = notification.userInfo;

    uint64_t addr = [userInfo[@"address"] unsignedLongLongValue];
    SSBreakpointType type = (SSBreakpointType)[userInfo[@"type"] intValue];
    uint64_t val = [userInfo[@"value"] unsignedLongLongValue];
    uint64_t instructionAddr = [userInfo[@"pc"] unsignedLongLongValue];
    uint64_t memoryAddress = [userInfo[@"memoryAddress"] unsignedLongLongValue];
    uint32_t threadId = (uint32_t)[userInfo[@"threadId"] unsignedLongLongValue];
    uint8_t size = (uint8_t)[userInfo[@"size"] unsignedIntValue];
    NSDictionary *registers = userInfo[@"registers"];
    NSArray *callStack = userInfo[@"callStack"];

    [LoggingService log:@"[AccessViewModel] addr: 0x%llX, type: %d, val: 0x%llX, pc: 0x%llX, tid: %u, size: %u",
     addr, (int)type, val, instructionAddr, threadId, size];

    [self updateRecordForAddress:addr
                           value:val
                   instructionAddr:instructionAddr
                    memoryAddress:memoryAddress
                            type:type
                        threadId:threadId
                            size:size
                       registers:registers
                       callStack:callStack];
}

- (void)handleWatchpointAdded:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    uint64_t address = [userInfo[@"address"] unsignedLongLongValue];
    SSBreakpointType type = (SSBreakpointType)[userInfo[@"type"] intValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        AccessRecord *record = [self recordForAddress:address];
        if (!record) {
            record = [[AccessRecord alloc] init];
            record.address = address;
            record.type = type;
            record.timestamp = [NSDate date];
            record.enabled = YES;
            [self.watchAddresses addObject:@(address)];
            [self.mutableRecords addObject:record];
        }
        record.armed = YES;
        record.armError = nil;
        [self notifyUpdate];
    });
}

- (void)handleDebuggerStateChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isDebugging = [SSDebugger sharedInstance].isDebugging;

        if (self.isDebugging) {
            // 可能是从 TracePage 等其它入口启动的调试器：把本页启用的点补上
            [self rearmAllRecords];
        } else {
            for (AccessRecord *record in self.mutableRecords) {
                record.armed = NO;
            }
        }

        [self notifyDebugStateChanged];
    });
}

#pragma mark - Private Methods

- (void)updateRecordForAddress:(uint64_t)address
                         value:(uint64_t)value
                 instructionAddr:(uint64_t)instructionAddr
                  memoryAddress:(uint64_t)memoryAddress
                          type:(SSBreakpointType)type
                      threadId:(uint32_t)threadId
                          size:(uint8_t)size
                      registers:(NSDictionary *)registers
                      callStack:(NSArray *)callStack {

    AccessRecord *targetRecord = [self recordForAddress:address];

    if (!targetRecord) {
        targetRecord = [[AccessRecord alloc] init];
        targetRecord.address = address;
        targetRecord.enabled = YES;
        [_mutableRecords addObject:targetRecord];
        [_watchAddresses addObject:@(address)];
    }

    NSDate *now = [NSDate date];

    targetRecord.value = value;
    targetRecord.hasValue = YES;
    targetRecord.instructionAddr = instructionAddr;
    targetRecord.type = type;
    targetRecord.hitCount++;
    targetRecord.timestamp = now;
    targetRecord.lastHitAt = now;
    targetRecord.lastThreadId = threadId;
    targetRecord.registers = registers;
    targetRecord.callStack = callStack;
    targetRecord.armed = YES;
    targetRecord.armError = nil;

    AccessHit *existingHit = nil;
    for (AccessHit *hit in targetRecord.history) {
        if (hit.instructionAddr == instructionAddr) {
            existingHit = hit;
            break;
        }
    }

    if (existingHit) {
        existingHit.value = value;
        existingHit.type = type;
        existingHit.timestamp = now;
        existingHit.hitCount++;
        existingHit.registers = registers;
        existingHit.callStack = callStack;
        existingHit.memoryAddress = memoryAddress;
        existingHit.threadId = threadId;
        existingHit.accessSize = size;
    } else {
        while (targetRecord.history.count >= kMaxHistoryCount) {
            [targetRecord.history removeObjectAtIndex:0];
        }

        AccessHit *newHit = [[AccessHit alloc] init];
        newHit.value = value;
        newHit.instructionAddr = instructionAddr;
        newHit.memoryAddress = memoryAddress;
        newHit.type = type;
        newHit.timestamp = now;
        newHit.hitCount = 1;
        newHit.registers = registers;
        newHit.callStack = callStack;
        newHit.threadId = threadId;
        newHit.accessSize = size;
        [targetRecord.history addObject:newHit];
    }

    // 访问页用这条通知做行内刷新；结构变化才走 notifyUpdate
    [[NSNotificationCenter defaultCenter] postNotificationName:kAccessRecordDidUpdateNotification
                                                        object:targetRecord];
}

- (void)notifyUpdate {
    if (self.hasPendingUpdate) {
        [LoggingService log:@"AccessViewModel: 已有待处理更新，跳过"];
        return;
    }

    self.hasPendingUpdate = YES;
    __weak typeof(self) weakSelf = self;
    self.pendingNotifyBlock = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf.hasPendingUpdate = NO;
        strongSelf.pendingNotifyBlock = nil;

        [LoggingService log:@"AccessViewModel: 发送更新通知"];
        [[NSNotificationCenter defaultCenter] postNotificationName:AccessViewModelDidUpdateNotification
                                                            object:strongSelf];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kNotifyDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   self.pendingNotifyBlock);
}

- (void)notifyDebugStateChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:AccessViewModelDebugStateChangedNotification
                                                        object:self];
}

@end
