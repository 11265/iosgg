#import "UI/Pages/Memory/MemoryPage+Batch.h"
#import "UI/Pages/Memory/MemoryPage+Private.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Components/ThemeConfig.h"
#import "UI/Components/MemoryCell.h"
#import "Models/DisplayItem.h"
#import "Services/LogService.h"
#import "Modules/Disassembly/InstructionBrowser.h"
#import "Modules/Disassembly/ARM64Assembler.h"
#import "UI/Pages/Record/RecordPage.h"

@implementation MemoryPages (Batch)

- (void)copySelectionTapped {
    if (self.selectedIndexes.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                       message:@"请先选择要复制的内容" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSMutableArray *lines = [NSMutableArray array];
    NSArray *sortedIndexes = [[self.selectedIndexes allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
        return [obj1 compare:obj2];
    }];
    
    for (NSNumber *selectedIndex in sortedIndexes) {
        NSInteger row = [selectedIndex integerValue];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        MemoryCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        
        if (cell) {
            NSString *addressText = cell.addressLabel.text ?: @"";
            NSString *valueText = cell.valueLabel.text ?: @"";
            NSString *line = [NSString stringWithFormat:@"%@\t%@", addressText, valueText];
            [lines addObject:line];
        }
    }
    
    NSString *copiedText = [lines componentsJoinedByString:@"\n"];
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = copiedText;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"复制成功" 
                                                                   message:[NSString stringWithFormat:@"已复制 %lu 行内容到剪贴板", (unsigned long)lines.count]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    
    [LoggingService log:@"[内存页面] 复制了 %lu 行内容", (unsigned long)lines.count];
}

- (void)exportAllButtonTapped {
    NSMutableArray *lines = [NSMutableArray array];
    
    if (self.selectedTypeIndex == 4) {
        for (DisplayItem *item in self.displayItems) {
            NSString *addrStr = [NSString stringWithFormat:@"0x%09llX", item.instruction.address];
            NSMutableString *valueStr = [NSMutableString string];
            for (int i = 0; i < item.depth; i++) {
                [valueStr appendString:@"    "];
            }
            [valueStr appendFormat:@"%@ %@", item.instruction.mnemonic ?: @"?", item.instruction.opStr ?: @""];
            [lines addObject:[NSString stringWithFormat:@"%@\t%@", addrStr, valueStr]];
        }
    } else {
        NSInteger totalRows = [self tableView:self.tableView numberOfRowsInSection:0];
        for (NSInteger row = 0; row < totalRows; row++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
            MemoryCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (cell) {
                NSString *addressText = cell.addressLabel.text ?: @"";
                NSString *valueText = cell.valueLabel.text ?: @"";
                [lines addObject:[NSString stringWithFormat:@"%@\t%@", addressText, valueText]];
            }
        }
    }
    
    if (lines.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"没有可复制的内容"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSString *copiedText = [lines componentsJoinedByString:@"\n"];
    UIPasteboard.generalPasteboard.string = copiedText;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"复制成功"
                                                                   message:[NSString stringWithFormat:@"已复制 %lu 行内容到剪贴板", (unsigned long)lines.count]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    
    [LoggingService log:@"[内存页面] 全部复制了 %lu 行内容", (unsigned long)lines.count];
}

- (void)cancelSelectionTapped {
    [self.selectedIndexes removeAllObjects];
    self.selectionCountLabel.text = @"0";
    [self.tableView reloadData];
}

- (void)saveButtonTapped {
    if (self.selectedIndexes.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"请先选择要保存的地址" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    RecordPage *recordVC = [FloatingWindow sharedInstance].recordViewController;
    if (!recordVC) return;
    
    NSString *type;
    switch (self.selectedTypeIndex) {
        case 0: type = @"i32"; break;
        case 1: type = @"i64"; break;
        case 2: type = @"f32"; break;
        case 3: type = @"f64"; break;
        case 4: type = @"i32"; break;
        default: type = @"i32"; break;
    }
    
    NSMutableArray *savedData = [NSMutableArray array];
    for (NSNumber *selectedIndex in self.selectedIndexes) {
        int64_t offset = ([selectedIndex integerValue] - 150) * 4;
        uint64_t address = self.baseAddress + offset;
        [savedData addObject:@{
            @"address": [NSString stringWithFormat:@"0x%llX", address],
            @"type": type
        }];
    }
    
    [recordVC addAddressesToRecord:savedData];
    [self.selectedIndexes removeAllObjects];
    self.selectionCountLabel.text = @"0";
    [self.tableView reloadData];
}

- (void)updateMemoryValues {
    NSArray *visibleCells = [self.tableView visibleCells];
    NSMutableArray *tasks = [NSMutableArray arrayWithCapacity:visibleCells.count];
    
    for (MemoryCell *cell in visibleCells) {
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        if (!indexPath) continue;
        
        NSMutableDictionary *task = [NSMutableDictionary dictionary];
        task[@"cell"] = cell;
        task[@"type"] = @(self.selectedTypeIndex);
        
        if (self.selectedTypeIndex == 4) {
             if (indexPath.row >= self.displayItems.count) continue;
             DisplayItem *item = self.displayItems[indexPath.row];
             task[@"address"] = @(item.instruction.address);
             task[@"depth"] = @(item.depth);
        } else {
             int64_t offset = (indexPath.row - 150) * 4;
             uint64_t address = self.baseAddress + offset;
             task[@"address"] = @(address);
        }
        [tasks addObject:task];
    }
    
    dispatch_async(self.updateQueue, ^{
        for (NSDictionary *task in tasks) {
            MemoryCell *cell = task[@"cell"];
            uint64_t address = [task[@"address"] unsignedLongLongValue];
            NSInteger type = [task[@"type"] integerValue];
            
            NSString *valueStr = @"???";
            NSString *addressKey = [NSString stringWithFormat:@"%lld", address];
            NSError *error = nil;
            
            switch (type) {
                case 0: {
                    uint32_t value = (uint32_t)[self.instructionBrowser readMemoryAtAddress:address size:4 error:&error];
                    if (!error) valueStr = [NSString stringWithFormat:@"%u", value];
                    break;
                }
                case 1: {
                    uint64_t value = [self.instructionBrowser readMemoryAtAddress:address size:8 error:&error];
                    if (!error) valueStr = [NSString stringWithFormat:@"%llu", value];
                    break;
                }
                case 2: {
                    uint32_t intValue = (uint32_t)[self.instructionBrowser readMemoryAtAddress:address size:4 error:&error];
                    if (!error) {
                        float floatValue;
                        memcpy(&floatValue, &intValue, sizeof(float));
                        valueStr = [NSString stringWithFormat:@"%f", floatValue];
                    }
                    break;
                }
                case 3: {
                    uint64_t intValue = [self.instructionBrowser readMemoryAtAddress:address size:8 error:&error];
                    if (!error) {
                        double doubleValue;
                        memcpy(&doubleValue, &intValue, sizeof(double));
                        valueStr = [NSString stringWithFormat:@"%lf", doubleValue];
                    }
                    break;
                }
                case 4: {
                    uint32_t val = (uint32_t)[self.instructionBrowser readMemoryAtAddress:address size:4 error:&error];
                    if (!error) {
                        DisassembledInstruction *d = [ARM64Assembler disassemble:val atAddress:address];
                        NSMutableString *s = [NSMutableString string];
                        int depth = [task[@"depth"] intValue];
                        for(int i=0; i<depth; i++) [s appendString:@"    "];
                        if ([d.mnemonic isEqualToString:@".word"]) {
                            [s appendFormat:@".word 0x%08x", d.value];
                        } else {
                            [s appendFormat:@"%@ %@", d.mnemonic, d.opStr];
                        }
                        valueStr = s;
                    }
                    break;
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSIndexPath *currentIndexPath = [self.tableView indexPathForCell:cell];
                if (currentIndexPath) {
                    cell.valueLabel.text = valueStr;
                    
                    NSString *previousValue = self.previousValues[addressKey];
                    if (previousValue && ![previousValue isEqualToString:valueStr]) {
                        self.cellColors[addressKey] = [UIColor yellowColor];
                        cell.valueLabel.textColor = [UIColor yellowColor];
                        
                        NSTimer *existingTimer = self.colorResetTimers[addressKey];
                        [existingTimer invalidate];
                        
                        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
                            self.cellColors[addressKey] = IMGUI_TEXT;
                            [self.colorResetTimers removeObjectForKey:addressKey];
                            [self.tableView reloadRowsAtIndexPaths:@[currentIndexPath] withRowAnimation:UITableViewRowAnimationNone];
                        }];
                        
                        self.colorResetTimers[addressKey] = timer;
                        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
                    }
                    self.previousValues[addressKey] = valueStr;
                }
            });
        }
    });
}

@end
