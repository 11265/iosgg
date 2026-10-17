#import "UI/Pages/Debugger/TracePage+Debugger.h"
#import "UI/Pages/Debugger/TracePage+Private.h"
#import "Modules/Debugger/SSDebugger.h"
#import "Services/LogService.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Pages/Memory/MemoryPage.h"
#import "UI/Dialogs/RegisterStateDialog.h"

@implementation SSTrackPopViewController (Debugger)

- (void)startDebugging {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    
    if (debugger.isDebugging) {
        [LoggingService log:@"调试器已经在运行"];
        self.isDebugging = YES;
        [self updateButtonStates];
        return;
    }
    
    NSError *error = nil;
    pid_t pid = getpid();
    
    [debugger stopDebug];
    self.isDebugging = NO;
    
    [self.watchAddresses removeAllObjects];
    [self.trackingData removeAllObjects];
    [self.tableView reloadData];
    
    if ([debugger startDebugWithPid:pid]) {
        self.isDebugging = YES;
        [LoggingService log:@"调试器启动成功"];
        [self updateButtonStates];
    } else {
        [LoggingService log:@"调试器启动失败: %@", error.localizedDescription];
        self.startDebugButton.enabled = YES;
        self.stopDebugButton.enabled = NO;
        self.watchButton.enabled = NO;
        self.clearButton.enabled = NO;
    }
}

- (void)stopDebugging {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    
    if (!self.isDebugging && !debugger.isDebugging) {
        [LoggingService log:@"调试器未运行"];
        return;
    }
    
    [self removeAllWatchpoints];
    [debugger stopDebug];
    self.isDebugging = NO;
    [LoggingService log:@"调试已停止"];
    [self updateButtonStates];
}

- (void)addMemoryWatchpoint:(uint64_t)address size:(size_t)size type:(SSBreakpointType)type {
    [LoggingService log:@"[addMemoryWatchpoint] 开始添加监视点: 地址=0x%llX, 大小=%zu, 类型=%ld", address, size, (long)type];
    
    SSDebugger *debugger = [SSDebugger sharedInstance];
    
    if (!debugger.isDebugging) {
        [LoggingService log:@"检测到调试器未运行，正在尝试启动..."];
        [self startDebugging];
        if (!debugger.isDebugging) {
            [LoggingService log:@"调试器启动失败，无法添加监视点"];
            return;
        }
    }
    
    if (self.isDebugging != debugger.isDebugging) {
        self.isDebugging = debugger.isDebugging;
        [self updateButtonStates];
    }
    
    NSError *error = nil;
    
    [debugger watchAddress:address size:size type:type callback:^(void *addr, SSBreakpointType type, uint64_t value, uint64_t instructionAddr) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SSTrackRecord *existingRecord = nil;
            for (SSTrackRecord *record in self.trackingData) {
                if (record.address == (uint64_t)addr && record.instructionAddr == instructionAddr) {
                    existingRecord = record;
                    break;
                }
            }
            
            if (existingRecord) {
                existingRecord.value = value;
                existingRecord.hitCount++;
                existingRecord.timestamp = [NSDate date];
                if ([self.trackingData indexOfObject:existingRecord] != 0) {
                    [self.trackingData removeObject:existingRecord];
                    [self.trackingData insertObject:existingRecord atIndex:0];
                }
            } else {
                SSTrackRecord *record = [[SSTrackRecord alloc] init];
                record.address = (uint64_t)addr;
                record.value = value;
                record.instructionAddr = instructionAddr;
                record.type = type;
                record.timestamp = [NSDate date];
                record.hitCount = 1;
                [self.trackingData insertObject:record atIndex:0];
                if (self.trackingData.count > 100) {
                    [self.trackingData removeLastObject];
                }
            }
            
            [self.tableView reloadData];
        });
    } error:&error];
    
    if (error) {
        [LoggingService log:@"添加监视点失败: %@", error.localizedDescription];
    } else {
        [self.watchAddresses addObject:@(address)];
        [LoggingService log:@"成功添加监视点: 地址=0x%llx, 大小=%zu", address, size];
    }
}

- (void)watchButtonTapped {
    if (!self.isDebugging) {
        [LoggingService log:@"请先启动调试器"];
        return;
    }
    
    NSString *addressStr = self.addressField.text;
    if (addressStr.length == 0) {
        [LoggingService log:@"请输入地址"];
        return;
    }
    
    uint64_t address = strtoull(addressStr.UTF8String, NULL, 16);
    if ([self.watchAddresses containsObject:@(address)]) {
        [LoggingService log:@"该地址已经在监视中: 0x%llx", address];
        return;
    }
    for (SSTrackRecord *record in self.trackingData) {
        if (record.address == address && record.instructionAddr == 0) {
            [LoggingService log:@"该地址已经在监视中: 0x%llx", address];
            return;
        }
    }
    
    size_t size = 4;
    SSBreakpointType type = SSBreakpointTypeWrite;
    
    SSTrackRecord *record = [[SSTrackRecord alloc] init];
    record.address = address;
    record.value = 0;
    record.instructionAddr = 0;
    record.type = type;
    record.timestamp = [NSDate date];
    record.hitCount = 0;
    [self.trackingData insertObject:record atIndex:0];
    [self.tableView reloadData];
    
    SSDebugger *debugger = [SSDebugger sharedInstance];
    NSError *error = nil;
    
    [debugger watchAddress:address size:size type:type callback:^(void *addr, SSBreakpointType cbType, uint64_t value, uint64_t instructionAddr) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SSTrackRecord *existingRecord = nil;
            NSArray *currentData = [self.trackingData copy];
            for (SSTrackRecord *r in currentData) {
                if (r.address == (uint64_t)addr && r.instructionAddr == instructionAddr) {
                    existingRecord = r;
                    break;
                }
            }
            
            if (existingRecord) {
                existingRecord.value = value;
                existingRecord.hitCount++;
                existingRecord.timestamp = [NSDate date];
                if ([self.trackingData indexOfObject:existingRecord] != 0) {
                    [self.trackingData removeObject:existingRecord];
                    [self.trackingData insertObject:existingRecord atIndex:0];
                }
            } else {
                SSTrackRecord *record = [[SSTrackRecord alloc] init];
                record.address = (uint64_t)addr;
                record.value = value;
                record.instructionAddr = instructionAddr;
                record.type = cbType;
                record.timestamp = [NSDate date];
                record.hitCount = 1;
                [self.trackingData insertObject:record atIndex:0];
                if (self.trackingData.count > 100) {
                    [self.trackingData removeLastObject];
                }
            }
            
            [self.tableView reloadData];
        });
    } error:&error];
    
    if (error) {
        [self.trackingData removeObject:record];
        [self.tableView reloadData];
        [LoggingService log:@"添加监视点失败: %@", error.localizedDescription];
        return;
    }
    
    [self.watchAddresses addObject:@(address)];
    [LoggingService log:@"成功添加监视点: 地址=0x%llx, 大小=%zu", address, size];
}

- (void)clearButtonTapped {
    [self removeAllWatchpoints];
}

- (void)removeAllWatchpoints {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    for (NSNumber *address in self.watchAddresses) {
        [debugger removeWatchAtAddress:address.unsignedLongLongValue];
    }
    [self.watchAddresses removeAllObjects];
    [self.trackingData removeAllObjects];
    [self.tableView reloadData];
    [LoggingService log:@"已清除所有监视点"];
}

- (void)startButtonTapped {
    [self startDebugging];
}

- (void)stopButtonTapped {
    [self stopDebugging];
}

- (void)updateButtonStates {
    self.startDebugButton.enabled = !self.isDebugging;
    self.stopDebugButton.enabled = self.isDebugging;
    self.watchButton.enabled = self.isDebugging;
    self.clearButton.enabled = self.isDebugging;
}

@end
