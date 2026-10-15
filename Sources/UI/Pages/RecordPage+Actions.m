#import "UI/Pages/RecordPage+Actions.h"
#import "UI/Pages/RecordPage+Private.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Components/ThemeConfig.h"
#import "UI/Pages/AccessPage.h"
#import "UI/Dialogs/AddRecordDialog.h"
#import "Services/Memory/PointerChainParser.h"
#import "Services/LogService.h"
#import <mach/mach.h>
#import "Models/AccessViewModel.h"

@implementation RecordPage (Actions)

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
    
    NSArray *accessTypes = @[@"写入", @"读取", @"读写", @"执行"];
    
    for (NSInteger i = 0; i < accessTypes.count; i++) {
        NSString *title = accessTypes[i];
        SSBreakpointType type = SSBreakpointTypeWrite;
        if (i == 1) type = SSBreakpointTypeRead;
        else if (i == 2) type = SSBreakpointTypeReadWrite;
        else if (i == 3) type = SSBreakpointTypeExecute;
        
        SSBreakpointType finalType = type;
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [self addSelectedToAccessPageWithType:finalType];
        }];
        [accessAlert addAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [accessAlert addAction:cancelAction];
    
    [self presentViewController:accessAlert animated:YES completion:nil];
}

- (void)addSelectedToAccessPageWithType:(SSBreakpointType)type {
    AccessPage *accessPage = [FloatingWindow sharedInstance].accessViewController;
    if (!accessPage) {
        [LoggingService log:@"记录页面: 无法获取访问页"];
        return;
    }
    
    [LoggingService log:@"记录页面: 获取到访问页, viewModel=%@", accessPage.viewModel];
    
    NSInteger addedCount = 0;
    for (NSNumber *index in self.selectedIndexes) {
        NSInteger row = [index integerValue];
        if (row >= self.savedAddresses.count) continue;
        
        NSDictionary *addressInfo = self.savedAddresses[row];
        NSString *addressStr = addressInfo[@"address"];
        
        if ([addressInfo[@"isPointerChain"] boolValue]) {
            NSArray *chain = addressInfo[@"pointerChain"];
            
            uint64_t moduleBase = 0;
            if (chain.count > 0) {
                NSDictionary *firstStep = chain[0];
                if ([firstStep[@"type"] isEqualToString:@"module"]) {
                    NSString *moduleName = firstStep[@"module"];
                    moduleBase = [PointerChainResolver getModuleBase:moduleName];
                }
            }
            
            NSError *error = nil;
            uint64_t resolvedAddr = [PointerChainResolver resolvePointerChain:chain 
                                                                   moduleBase:moduleBase 
                                                                        error:&error];
            if (error || resolvedAddr == 0) {
                [LoggingService log:@"记录页面: 无法解析指针链: %@", addressInfo[@"chainExpression"]];
                continue;
            }
            [LoggingService log:@"记录页面: 添加指针链地址 0x%llx 类型=%d", resolvedAddr, type];
            [accessPage.viewModel addWatchpoint:resolvedAddr type:type];
            addedCount++;
        } else {
            uint64_t address = strtoull([addressStr UTF8String], NULL, 16);
            if (address != 0) {
                [LoggingService log:@"记录页面: 添加地址 0x%llx 类型=%d", address, type];
                [accessPage.viewModel addWatchpoint:address type:type];
                addedCount++;
            }
        }
    }
    
    [LoggingService log:@"记录页面: 已添加 %ld 个地址到访问页, 当前记录数=%lu", (long)addedCount, (unsigned long)accessPage.viewModel.watchpointCount];
    
    [self.selectedIndexes removeAllObjects];
    [self.tableView reloadData];
}

- (void)clearButtonTapped {
    [self.savedAddresses removeAllObjects];
    [self buildAddressIndexMap];
    self.countLabel.text = @"Count: 0";
    [self.tableView reloadData];
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
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确定"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        NSString *newValue = alert.textFields.firstObject.text;
        if (newValue.length > 0) {
            [self modifyAllAddressesWithValue:newValue];
        }
    }];
    
    [alert addAction:confirmAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)modifyAllAddressesWithValue:(NSString *)valueStr {
    for (NSDictionary *addressInfo in self.savedAddresses) {
        NSString *address = addressInfo[@"address"];
        NSString *type = addressInfo[@"type"];
        uint64_t addressValue;
        NSScanner *scanner = [NSScanner scannerWithString:address];
        [scanner scanHexLongLong:&addressValue];
        
        uint64_t newValue = 0;
        if ([type isEqualToString:@"i32"]) {
            newValue = (uint64_t)[valueStr intValue];
        } else if ([type isEqualToString:@"i64"]) {
            newValue = (uint64_t)[valueStr longLongValue];
        } else if ([type isEqualToString:@"f32"]) {
            union { float f; uint32_t i; } u;
            u.f = [valueStr floatValue];
            newValue = u.i;
        } else if ([type isEqualToString:@"f64"]) {
            union { double d; uint64_t i; } u;
            u.d = [valueStr doubleValue];
            newValue = u.i;
        }
        
        mach_vm_write(mach_task_self(), addressValue, (vm_offset_t)&newValue, sizeof(newValue));
    }
    [self updateAllValues];
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
        NSDictionary *addressInfo = self.savedAddresses[selectedIndex.integerValue];
        NSString *address = addressInfo[@"address"];
        NSString *type = addressInfo[@"type"];
        uint64_t addressValue;
        NSScanner *scanner = [NSScanner scannerWithString:address];
        [scanner scanHexLongLong:&addressValue];
        
        uint64_t newValue = 0;
        if ([type isEqualToString:@"i32"]) {
            newValue = (uint64_t)[valueStr intValue];
        } else if ([type isEqualToString:@"i64"]) {
            newValue = (uint64_t)[valueStr longLongValue];
        } else if ([type isEqualToString:@"f32"]) {
            union { float f; uint32_t i; } u;
            u.f = [valueStr floatValue];
            newValue = u.i;
        } else if ([type isEqualToString:@"f64"]) {
            union { double d; uint64_t i; } u;
            u.d = [valueStr doubleValue];
            newValue = u.i;
        }
        
        mach_vm_write(mach_task_self(), addressValue, (vm_offset_t)&newValue, sizeof(newValue));
    }
    [self updateAllValues];
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
    NSInteger firstIndex = [selectedIndexArray[0] integerValue];
    NSInteger secondIndex = [selectedIndexArray[1] integerValue];

    NSDictionary *firstAddressInfo = self.savedAddresses[firstIndex];
    NSDictionary *secondAddressInfo = self.savedAddresses[secondIndex];

    uint64_t firstAddress = 0;
    uint64_t secondAddress = 0;
    [[NSScanner scannerWithString:firstAddressInfo[@"address"]] scanHexLongLong:&firstAddress];
    [[NSScanner scannerWithString:secondAddressInfo[@"address"]] scanHexLongLong:&secondAddress];

    int64_t offset = secondAddress - firstAddress;

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
