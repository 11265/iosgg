#import "UI/Pages/Record/RecordPage+Actions.h"
#import "UI/Pages/Record/RecordPage+Private.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Components/ThemeConfig.h"
#import "UI/Pages/Debugger/AccessPage.h"
#import "UI/Dialogs/AddRecordDialog.h"
#import "Modules/MemoryAnalysis/PointerChainParser.h"
#import "Services/LogService.h"
#import "Models/SSRecordStore.h"
#import "Models/SSDataTypeUtility.h"
#import <mach/mach.h>
#import "Models/AccessViewModel.h"

@implementation RecordPage (Actions)

- (SSRecordStore *)sharedStore { return [SSRecordStore sharedStore]; }

- (void)closeButtonTapped {
    [[FloatingWindow sharedInstance] hide];
}

- (void)accessButtonTapped {
    if (self.selectedIndexes.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"请先选择要监视的地址"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *accessAlert = [UIAlertController alertControllerWithTitle:@"选择访问类型"
                                                                        message:@"请选择监视类型"
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 访问点只保留两种语义：写入（只盯写）与访问（只盯读）
    NSArray *accessTypes = @[@"写入", @"访问"];
    
    for (NSInteger i = 0; i < accessTypes.count; i++) {
        SSBreakpointType type = (i == 0) ? SSBreakpointTypeWrite : SSBreakpointTypeRead;
        
        SSBreakpointType finalType = type;
        UIAlertAction *action = [UIAlertAction actionWithTitle:accessTypes[i]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [self addSelectedToAccessPageWithType:finalType];
        }];
        [accessAlert addAction:action];
    }
    
    [accessAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    
    [self presentViewController:accessAlert animated:YES completion:nil];
}

- (void)addSelectedToAccessPageWithType:(SSBreakpointType)type {
    AccessPage *accessPage = [FloatingWindow sharedInstance].accessViewController;
    if (!accessPage) {
        [LoggingService log:@"记录页面: 无法获取访问页"];
        return;
    }
    
    NSInteger addedCount = 0;
    NSInteger failedCount = 0;
    NSString *firstError = nil;

    for (NSNumber *index in self.selectedIndexes) {
        SSMemoryRecord *rec = [[self sharedStore] recordAtIndex:index.integerValue];
        if (!rec) continue;
        
        uint64_t address = [self resolvedAddressForRecord:rec];
        if (address == 0) {
            [LoggingService log:@"记录页面: 无法解析地址 %@", [rec displayAddressText]];
            failedCount++;
            continue;
        }

        NSError *error = nil;
        if ([accessPage.viewModel addWatchpoint:address type:type error:&error]) {
            addedCount++;
        } else {
            failedCount++;
            if (firstError.length == 0) {
                firstError = error.localizedDescription;
            }
        }
    }
    
    [LoggingService log:@"记录页面: 已添加 %ld 个地址到访问页（失败 %ld）, 当前监视数=%lu",
     (long)addedCount, (long)failedCount, (unsigned long)accessPage.viewModel.watchpointCount];

    if (failedCount > 0) {
        NSString *message = [NSString stringWithFormat:
            @"成功 %ld 个，失败 %ld 个。\n%@",
            (long)addedCount, (long)failedCount, firstError ?: @"未知错误"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加访问点"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    
    [self.selectedIndexes removeAllObjects];
    [self.tableView reloadData];
}

- (void)clearButtonTapped {
    [[self sharedStore] removeAll];   // Store 会发通知，RecordPage 监听后刷新
    [LoggingService log:@"记录页面: 清除所有记录"];
}

- (void)addButtonTapped {
    SSAddRecordPopViewController *vc = [SSAddRecordPopViewController addRecordPopViewController];
    [self addChildViewController:vc];
    [self.view addSubview:vc.view];
    vc.view.frame = self.view.bounds;
    [vc didMoveToParentViewController:self];
}

- (void)modifyAllButtonTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改所有值"
                                                                 message:@"请输入要修改的值"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.placeholder = @"输入新的值";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        NSString *newValue = alert.textFields.firstObject.text;
        if (newValue.length > 0) {
            [self modifyAllAddressesWithValue:newValue];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)modifyAllAddressesWithValue:(NSString *)valueStr {
    for (SSMemoryRecord *rec in [self sharedStore].records) {
        [self writeValue:valueStr toRecord:rec];
    }
    [self updateAllValues];
}

- (void)modifySelectedButtonTapped {
    if (!self.isSelectionMode || self.selectedIndexes.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"请先进入选择模式并选择地址"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改选中值"
                                                                 message:[NSString stringWithFormat:@"修改 %lu 个选中项", (unsigned long)self.selectedIndexes.count]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.placeholder = @"输入新的值";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newValue = alert.textFields.firstObject.text;
        if (newValue.length > 0) {
            [self modifySelectedAddressesWithValue:newValue];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)modifySelectedAddressesWithValue:(NSString *)valueStr {
    for (NSNumber *selectedIndex in self.selectedIndexes) {
        SSMemoryRecord *rec = [[self sharedStore] recordAtIndex:selectedIndex.integerValue];
        if (rec) [self writeValue:valueStr toRecord:rec];
    }
    [self updateAllValues];
}

/// 统一的写值入口：解析输入 → 按类型宽度写入（走 SSDataTypeUtility）
- (void)writeValue:(NSString *)valueStr toRecord:(SSMemoryRecord *)rec {
    uint64_t address = [self resolvedAddressForRecord:rec];
    if (address == 0) return;
    
    uint64_t newValue = [SSDataTypeUtility rawValueFromInput:valueStr type:rec.type];
    mach_msg_type_number_t writeSize = (mach_msg_type_number_t)[SSDataTypeUtility widthForType:rec.type];
    mach_vm_write(mach_task_self(), address, (vm_offset_t)&newValue, writeSize);
}

- (void)selectButtonTapped:(UIButton *)sender {
    self.isSelectionMode = !self.isSelectionMode;
    if (self.isSelectionMode) {
        sender.backgroundColor = IMGUI_BUTTON_ACTIVE;
        [sender setTitle:@"取消" forState:UIControlStateNormal];
    } else {
        sender.backgroundColor = IMGUI_BUTTON;
        [sender setTitle:@"选择" forState:UIControlStateNormal];
        [self.selectedIndexes removeAllObjects];
        [self.tableView reloadData];
    }
    [LoggingService log:@"记录页面: %@选择模式", self.isSelectionMode ? @"进入" : @"退出"];
}

- (void)calculateButtonTapped {
    if (!self.isSelectionMode || self.selectedIndexes.count != 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"请选择两个地址进行计算"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSArray *selectedIndexArray = [self.selectedIndexes.allObjects sortedArrayUsingSelector:@selector(compare:)];
    SSMemoryRecord *firstRec = [[self sharedStore] recordAtIndex:[selectedIndexArray[0] integerValue]];
    SSMemoryRecord *secondRec = [[self sharedStore] recordAtIndex:[selectedIndexArray[1] integerValue]];
    if (!firstRec || !secondRec) return;

    int64_t offset = (int64_t)secondRec.address - (int64_t)firstRec.address;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"偏移计算结果"
                                                                 message:[NSString stringWithFormat:@"偏移值: %lld (0x%llX)", offset, (uint64_t)llabs(offset)]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"复制十进制" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"%lld", offset];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"复制十六进制" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"0x%llX", (uint64_t)llabs(offset)];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
