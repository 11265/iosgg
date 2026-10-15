#import "Models/AccessViewModel.h"
#import "Models/AccessRecord.h"
#import "Services/LogService.h"

NSNotificationName const AccessViewModelDidUpdateNotification = @"AccessViewModelDidUpdateNotification";
NSNotificationName const AccessViewModelDebugStateChangedNotification = @"AccessViewModelDebugStateChangedNotification";

static const NSInteger kMaxHistoryCount = 50;
static const NSTimeInterval kNotifyDebounceInterval = 0.1;

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

#pragma mark - Watchpoint Management

- (void)addWatchpoint:(uint64_t)address type:(SSBreakpointType)type {
    [LoggingService log:@"AccessViewModel: addWatchpoint 地址=0x%llx 类型=%d", address, type];
    
    SSDebugger *debugger = [SSDebugger sharedInstance];
    if (!debugger.isDebugging) {
        [LoggingService log:@"AccessViewModel: 调试器未启动，正在启动..."];
        BOOL started = [debugger startDebugWithPid:getpid()];
        if (!started) {
            [LoggingService log:@"AccessViewModel: 启动调试器失败"];
            return;
        }
        [LoggingService log:@"AccessViewModel: 调试器已启动"];
    }
    
    if ([self addressExists:address]) {
        [LoggingService log:@"AccessViewModel: 地址已存在，跳过"];
        return;
    }
    
    NSError *error = nil;
    BOOL success = [debugger watchAddress:address 
                                      size:8 
                                      type:type 
                                  callback:nil 
                                    error:&error];
    if (!success) {
        [LoggingService log:@"AccessViewModel: 添加watchpoint失败: %@", error.localizedDescription];
        return;
    }
    
    [_watchAddresses addObject:@(address)];
    
    AccessRecord *record = [[AccessRecord alloc] init];
    record.address = address;
    record.type = type;
    record.timestamp = [NSDate date];
    [_mutableRecords addObject:record];
    
    [LoggingService log:@"AccessViewModel: 成功添加记录，当前记录数=%lu", (unsigned long)_mutableRecords.count];
    [self notifyUpdate];
}

- (void)removeWatchpointAtIndex:(NSUInteger)index {
    if (index >= _mutableRecords.count) return;
    
    AccessRecord *record = _mutableRecords[index];
    uint64_t address = record.address;
    
    [[SSDebugger sharedInstance] removeWatchAtAddress:address];
    
    [_watchAddresses removeObject:@(address)];
    [_mutableRecords removeObjectAtIndex:index];
    
    [self notifyUpdate];
}

- (void)removeAllWatchpoints {
    for (AccessRecord *record in _mutableRecords) {
        [[SSDebugger sharedInstance] removeWatchAtAddress:record.address];
    }
    
    [_watchAddresses removeAllObjects];
    [_mutableRecords removeAllObjects];
    
    [self notifyUpdate];
}

- (void)setEnabled:(BOOL)enabled forAddress:(uint64_t)address {
    AccessRecord *targetRecord = nil;
    for (AccessRecord *record in _mutableRecords) {
        if (record.address == address) {
            targetRecord = record;
            break;
        }
    }
    
    if (!targetRecord) return;
    
    targetRecord.enabled = enabled;
    
    if (!enabled) {
        [[SSDebugger sharedInstance] removeWatchAtAddress:address];
    } else {
        NSError *error = nil;
        [[SSDebugger sharedInstance] watchAddress:address 
                                             size:8 
                                             type:targetRecord.type 
                                         callback:nil 
                                           error:&error];
    }
    
    [self notifyUpdate];
}

- (void)setType:(SSBreakpointType)type forAddress:(uint64_t)address {
    AccessRecord *targetRecord = nil;
    for (AccessRecord *record in _mutableRecords) {
        if (record.address == address) {
            targetRecord = record;
            break;
        }
    }
    
    if (!targetRecord) return;
    
    targetRecord.type = type;
    
    if (targetRecord.enabled) {
        [[SSDebugger sharedInstance] removeWatchAtAddress:address];
        
        NSError *error = nil;
        [[SSDebugger sharedInstance] watchAddress:address 
                                             size:8 
                                             type:type 
                                         callback:nil 
                                           error:&error];
    }
    
    [self notifyUpdate];
}

- (BOOL)addressExists:(uint64_t)address {
    for (NSNumber *addrNum in _watchAddresses) {
        if ([addrNum unsignedLongLongValue] == address) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Debugging Control

- (void)startDebugging {
    [[SSDebugger sharedInstance] startDebugWithPid:getpid()];
}

- (void)stopDebugging {
    [[SSDebugger sharedInstance] stopDebug];
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

- (void)syncWithDebugger {
    self.isDebugging = [SSDebugger sharedInstance].isDebugging;
    
    NSDictionary *watched = [[SSDebugger sharedInstance] getAllWatchedAddresses];
    for (NSNumber *addrNum in watched) {
        uint64_t addr = [addrNum unsignedLongLongValue];
        if (![self addressExists:addr]) {
            [_watchAddresses addObject:addrNum];
            SSBreakpointType type = (SSBreakpointType)[watched[addrNum] intValue];
            
            AccessRecord *record = [[AccessRecord alloc] init];
            record.address = addr;
            record.type = type;
            record.timestamp = [NSDate date];
            [_mutableRecords addObject:record];
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
    NSDictionary *registers = userInfo[@"registers"];
    NSArray *callStack = userInfo[@"callStack"];
    
    [LoggingService log:@"[AccessViewModel] addr: 0x%llX, type: %d, val: 0x%llX, pc: 0x%llX", addr, (int)type, val, instructionAddr];
    
    [self updateRecordForAddress:addr
                           value:val
                   instructionAddr:instructionAddr
                    memoryAddress:memoryAddress
                            type:type
                       registers:registers
                       callStack:callStack];
}

- (void)handleWatchpointAdded:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    uint64_t address = [userInfo[@"address"] unsignedLongLongValue];
    SSBreakpointType type = (SSBreakpointType)[userInfo[@"type"] intValue];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self addressExists:address]) {
            [self.watchAddresses addObject:@(address)];
            
            AccessRecord *record = [[AccessRecord alloc] init];
            record.address = address;
            record.type = type;
            record.timestamp = [NSDate date];
            [self.mutableRecords addObject:record];
            
            [self notifyUpdate];
        }
    });
}

- (void)handleDebuggerStateChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isDebugging = [SSDebugger sharedInstance].isDebugging;
        [self notifyDebugStateChanged];
    });
}

#pragma mark - Private Methods

- (void)updateRecordForAddress:(uint64_t)address
                         value:(uint64_t)value
                 instructionAddr:(uint64_t)instructionAddr
                  memoryAddress:(uint64_t)memoryAddress
                          type:(SSBreakpointType)type
                     registers:(NSDictionary *)registers
                     callStack:(NSArray *)callStack {
    
    AccessRecord *targetRecord = nil;
    for (AccessRecord *record in _mutableRecords) {
        if (record.address == address) {
            targetRecord = record;
            break;
        }
    }
    
    if (!targetRecord) {
        targetRecord = [[AccessRecord alloc] init];
        targetRecord.address = address;
        [_mutableRecords addObject:targetRecord];
        [_watchAddresses addObject:@(address)];
    }
    
    targetRecord.value = value;
    targetRecord.instructionAddr = instructionAddr;
    targetRecord.type = type;
    targetRecord.hitCount++;
    targetRecord.timestamp = [NSDate date];
    targetRecord.registers = registers;
    targetRecord.callStack = callStack;
    
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
        existingHit.timestamp = targetRecord.timestamp;
        existingHit.hitCount++;
        existingHit.registers = registers;
        existingHit.callStack = callStack;
        existingHit.memoryAddress = memoryAddress;
    } else {
        while (targetRecord.history.count >= kMaxHistoryCount) {
            [targetRecord.history removeObjectAtIndex:0];
        }
        
        AccessHit *newHit = [[AccessHit alloc] init];
        newHit.value = value;
        newHit.instructionAddr = instructionAddr;
        newHit.memoryAddress = memoryAddress;
        newHit.type = type;
        newHit.timestamp = targetRecord.timestamp;
        newHit.hitCount = 1;
        newHit.registers = registers;
        newHit.callStack = callStack;
        [targetRecord.history addObject:newHit];
    }
    
    [self notifyUpdate];
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
