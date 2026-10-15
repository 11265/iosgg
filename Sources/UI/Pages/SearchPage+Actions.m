#import "UI/Pages/SearchPage+Actions.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Dialogs/EditValueDialog.h"
#import "UI/Dialogs/CompareDialog.h"
#import "UI/Dialogs/OffsetDialog.h"
#import "UI/Dialogs/SignatureDialog.h"
#import "UI/Dialogs/SearchDialog.h"
#import "UI/Dialogs/FuzzySearchDialog.h"
#import "UI/Dialogs/RegisterStateDialog.h"
#import "UI/Pages/TracePage.h"
#import "UI/Pages/RecordPage.h"
#import "Services/LogService.h"
#import "Services/ProcessMemory.h"
#import "Services/Scanner/Scanner.h"

// Re-declare private properties so the category can access them
@interface SearchPage ()
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) dispatch_queue_t updateQueue;
@property (nonatomic, strong) UISwitch *modeSwitch;
@property (nonatomic, strong) NSArray *searchModeButtons;
@property (nonatomic, strong) NSArray *editModeButtons;
@property (nonatomic, strong) NSMutableSet *selectedIndexes;
@end

// Forward-declare the internal method used by the callback
@interface SearchPage ()
- (void)updateSearchResults:(NSArray<NSNumber *> *)addresses withType:(SearchDataType)type;
@end

@implementation SearchPage (Actions)

- (void)searchTapped {
    [LoggingService log:@"开始显示搜索弹窗"];
    
    SSSearchPopViewController *searchPopVC = [SSSearchPopViewController searchPopViewController];
    [self addChildViewController:searchPopVC];
    [self.view addSubview:searchPopVC.view];
    
    searchPopVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [searchPopVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [searchPopVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [searchPopVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [searchPopVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [searchPopVC didMoveToParentViewController:self];
}

- (void)clearTapped {
    [LoggingService log:@"执行清除操作"];
    清理搜索();
    [[NSNotificationCenter defaultCenter] postNotificationName:kResetSearchNotification object:nil];
    [LoggingService log:@"清除操作完成"];
}

- (void)blurTapped {
    // 实现模糊功能
}

- (void)selectAllTapped {
    [self.selectedIndexes removeAllObjects];
    
    for (NSInteger i = 0; i < self.dataSource.count; i++) {
        [self.selectedIndexes addObject:@(i)];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
        [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    
    [LoggingService log:@"已全选 %lu 行", (unsigned long)self.dataSource.count];
}

- (void)invertSelectionTapped {
    NSMutableSet *newSelection = [NSMutableSet new];
    
    for (NSInteger i = 0; i < self.dataSource.count; i++) {
        NSNumber *index = @(i);
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
        
        if (![self.selectedIndexes containsObject:index]) {
            [newSelection addObject:index];
            [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        } else {
            [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
        }
    }
    
    self.selectedIndexes = newSelection;
    [LoggingService log:@"反选后选中了 %lu 行", (unsigned long)self.selectedIndexes.count];
}

- (void)saveTapped {
    if (self.selectedIndexes.count == 0) {
        [LoggingService log:@"搜索页面: 没有选中任何行，不执行保存"];
        return;
    }
    
    [LoggingService log:@"搜索页面: 开始保存 %lu 个选中的行", (unsigned long)self.selectedIndexes.count];
    
    NSMutableArray *savedData = [NSMutableArray array];
    for (NSNumber *index in self.selectedIndexes) {
        if (index.integerValue < self.dataSource.count) {
            NSAttributedString *attrStr = self.dataSource[index.integerValue];
            NSString *plainText = attrStr.string;
            
            NSArray *components = [plainText componentsSeparatedByString:@"    "];
            if (components.count >= 2) {
                NSString *address = components[0];
                NSString *type = components[1];
                
                [savedData addObject:@{
                    @"address": address,
                    @"type": type
                }];
                [LoggingService log:@"搜索页面: 添加地址 %@ 类型 %@", address, type];
            }
        }
    }
    
    RecordPage *recordVC = [FloatingWindow sharedInstance].recordViewController;
    if (recordVC) {
        [LoggingService log:@"搜索页面: 获取到记录视图控制器，准备添加 %lu 个地址", (unsigned long)savedData.count];
        [recordVC addAddressesToRecord:savedData];
        [LoggingService log:@"搜索页面: 数据已添加到记录页面"];
    } else {
        [LoggingService log:@"搜索页面: 错误 - 无法获取记录视图控制器"];
    }
    
    [self.selectedIndexes removeAllObjects];
    [self.tableView reloadData];
}

- (void)helpTapped {
    [LoggingService log:@"开始显示帮助/对比弹"];
    
    if (当前搜索模式 == 未搜索) {
        [LoggingService log:@"当前是未搜索状态，示帮助弹窗"];
        
        SSHelpPopViewController *helpPopVC = [SSHelpPopViewController helpPopViewController];
        [self addChildViewController:helpPopVC];
        [self.view addSubview:helpPopVC.view];
        
        helpPopVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [helpPopVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [helpPopVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [helpPopVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [helpPopVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
        
        [helpPopVC didMoveToParentViewController:self];
        
        helpPopVC.view.alpha = 0;
        [UIView animateWithDuration:0.25 animations:^{
            helpPopVC.view.alpha = 1;
        }];
        
        [LoggingService log:@"帮助弹窗已显示"];
    } else {
        [LoggingService log:@"当前已搜索，显示对比弹窗"];
        
        SSComparePopViewController *comparePopVC = [SSComparePopViewController comparePopViewController];
        [self addChildViewController:comparePopVC];
        [self.view addSubview:comparePopVC.view];
        
        comparePopVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [comparePopVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [comparePopVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [comparePopVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [comparePopVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
        
        [comparePopVC didMoveToParentViewController:self];
        
        comparePopVC.view.alpha = 0;
        [UIView animateWithDuration:0.25 animations:^{
            comparePopVC.view.alpha = 1;
        }];
    }
}

- (void)trackTapped {
    if (!self.trackPopVC) {
        self.trackPopVC = [SSTrackPopViewController trackPopViewController];
        
        [self addChildViewController:self.trackPopVC];
        [self.view addSubview:self.trackPopVC.view];
        
        self.trackPopVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.trackPopVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [self.trackPopVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.trackPopVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.trackPopVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
        
        [self.trackPopVC didMoveToParentViewController:self];
    }
    
    [self.trackPopVC show];
}

- (void)signatureTapped {
    [LoggingService log:@"显示特征码搜索弹窗"];
    
    SSSignaturePopViewController *signaturePopVC = [SSSignaturePopViewController signaturePopViewController];
    [self addChildViewController:signaturePopVC];
    [self.view addSubview:signaturePopVC.view];
    
    signaturePopVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [signaturePopVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [signaturePopVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [signaturePopVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [signaturePopVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [signaturePopVC didMoveToParentViewController:self];
}

- (void)offsetTapped {
    [LoggingService log:@"显示偏移弹窗"];
    
    SSOffsetPopViewController *offsetPopVC = [SSOffsetPopViewController offsetPopViewController];
    [self addChildViewController:offsetPopVC];
    [self.view addSubview:offsetPopVC.view];
    
    offsetPopVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [offsetPopVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [offsetPopVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [offsetPopVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [offsetPopVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [offsetPopVC didMoveToParentViewController:self];
}

- (void)calculateOffsetTapped {
    if (self.selectedIndexes.count != 2) {
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
    
    NSAttributedString *firstAttrStr = self.dataSource[firstIndex];
    NSAttributedString *secondAttrStr = self.dataSource[secondIndex];
    
    NSString *firstAddressStr = [firstAttrStr.string componentsSeparatedByString:@"    "][0];
    NSString *secondAddressStr = [secondAttrStr.string componentsSeparatedByString:@"    "][0];
    
    uint64_t firstAddress = 0;
    uint64_t secondAddress = 0;
    NSScanner *scanner1 = [NSScanner scannerWithString:firstAddressStr];
    NSScanner *scanner2 = [NSScanner scannerWithString:secondAddressStr];
    [scanner1 scanHexLongLong:&firstAddress];
    [scanner2 scanHexLongLong:&secondAddress];
    
    int64_t offset = secondAddress - firstAddress;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"偏移计算结果"
                                                                 message:[NSString stringWithFormat:@"偏移值: %lld (0x%llX)", offset, (uint64_t)llabs(offset)]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"复制十进制" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = [NSString stringWithFormat:@"%lld", offset];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"复制十六进制" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = [NSString stringWithFormat:@"0x%llX", (uint64_t)llabs(offset)];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
    
    [LoggingService log:@"计算偏移值 - 第一个地址: 0x%llX, 第二个地址: 0x%llX, 偏移: %lld", firstAddress, secondAddress, offset];
}

- (void)accessoryButtonTapped:(UIButton *)sender {
    CGPoint buttonPosition = [sender convertPoint:CGPointZero toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:buttonPosition];
    
    if (indexPath && indexPath.row < self.dataSource.count) {
        NSAttributedString *rowText = self.dataSource[indexPath.row];
        NSString *plainText = rowText.string;
        
        [LoggingService log:@"点击感叹号 - 原始文本: %@", plainText];
        
        NSArray *components = [plainText componentsSeparatedByString:@"    "];
        if (components.count == 0) {
            [LoggingService log:@"错误：无法解析文本"];
            return;
        }
        
        NSString *addressPart = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        uint64_t address = 0;
        NSScanner *scanner = [NSScanner scannerWithString:addressPart];
        if (![scanner scanHexLongLong:&address]) {
            [LoggingService log:@"错误：无法解析地址: %@", addressPart];
            return;
        }
        
        NSString *typeStr = nil;
        if (components.count >= 2) {
            typeStr = components[1];
        }
        
        SearchDataType dataType;
        if ([typeStr isEqualToString:@"i32"]) {
            dataType = SearchDataTypeI32;
        } else if ([typeStr isEqualToString:@"i64"]) {
            dataType = SearchDataTypeI64;
        } else if ([typeStr isEqualToString:@"f32"]) {
            dataType = SearchDataTypeF32;
        } else if ([typeStr isEqualToString:@"f64"]) {
            dataType = SearchDataTypeF64;
        } else if ([typeStr isEqualToString:@"u8"]) {
            dataType = SearchDataTypeU8;
        } else if ([typeStr isEqualToString:@"i16"]) {
            dataType = SearchDataTypeI16;
        } else if ([typeStr isEqualToString:@"ptr"]) {
            dataType = SearchDataTypePtr;
        } else {
            [LoggingService log:@"警告：无法识别的类型字符串: %@，使用默认类型", typeStr];
            dataType = SearchDataTypeI32;
        }
        
        [LoggingService log:@"点击感叹号 - 地址: 0x%llX, 类型: %d", address, (int)dataType];
        
        [self showModifyAlertForAddress:address type:dataType];
    }
}

- (void)showModifyAlertForAddress:(uint64_t)address type:(SearchDataType)type {
    uint64_t currentValue = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    mach_vm_size_t outsize;
    mach_vm_read_overwrite(mach_task_self(), address, size, (mach_vm_address_t)&currentValue, &outsize);
    
    NSString *currentValueStr = @"";
    switch(type) {
        case SearchDataTypeI32:
            currentValueStr = [NSString stringWithFormat:@"%d", (int32_t)currentValue];
            break;
        case SearchDataTypeI64:
            currentValueStr = [NSString stringWithFormat:@"%lld", (int64_t)currentValue];
            break;
        case SearchDataTypeF32: {
            uint32_t val = (uint32_t)currentValue;
            currentValueStr = [NSString stringWithFormat:@"%f", *(float*)&val];
            break;
        }
        case SearchDataTypeF64: {
            currentValueStr = [NSString stringWithFormat:@"%lf", *(double*)&currentValue];
            break;
        }
        case SearchDataTypeU8:
            currentValueStr = [NSString stringWithFormat:@"%u", (uint8_t)currentValue];
            break;
        case SearchDataTypeI16:
            currentValueStr = [NSString stringWithFormat:@"%d", (int16_t)currentValue];
            break;
        case SearchDataTypePtr:
            currentValueStr = [NSString stringWithFormat:@"0x%llX", currentValue];
            break;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改数值"
                                                                 message:[NSString stringWithFormat:@"地址: 0x%llX", address]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = currentValueStr;
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *input = alert.textFields.firstObject.text;
        if (!input || input.length == 0) return;
        
        uint64_t valueToWrite = 0;
        BOOL isHex = [input hasPrefix:@"0x"] || [input hasPrefix:@"0X"];
        
        switch(type) {
            case SearchDataTypeI32: {
                if (isHex) {
                    unsigned int hexValue;
                    [[NSScanner scannerWithString:input] scanHexInt:&hexValue];
                    valueToWrite = (uint64_t)(int32_t)hexValue;
                } else {
                    valueToWrite = (uint64_t)[input intValue];
                }
                break;
            }
            case SearchDataTypeI64: {
                if (isHex) {
                    unsigned long long hexValue;
                    [[NSScanner scannerWithString:input] scanHexLongLong:&hexValue];
                    valueToWrite = (uint64_t)(int64_t)hexValue;
                } else {
                    valueToWrite = (uint64_t)[input longLongValue];
                }
                break;
            }
            case SearchDataTypeF32: {
                float f = [input floatValue];
                valueToWrite = *(uint32_t*)&f;
                break;
            }
            case SearchDataTypeF64: {
                double d = [input doubleValue];
                valueToWrite = *(uint64_t*)&d;
                break;
            }
            case SearchDataTypeU8: {
                if (isHex) {
                    unsigned int hexValue;
                    [[NSScanner scannerWithString:input] scanHexInt:&hexValue];
                    valueToWrite = (uint64_t)(uint8_t)hexValue;
                } else {
                    valueToWrite = (uint64_t)(uint8_t)[input intValue];
                }
                break;
            }
            case SearchDataTypeI16: {
                if (isHex) {
                    unsigned int hexValue;
                    [[NSScanner scannerWithString:input] scanHexInt:&hexValue];
                    valueToWrite = (uint64_t)(int16_t)hexValue;
                } else {
                    valueToWrite = (uint64_t)(int16_t)[input intValue];
                }
                break;
            }
            case SearchDataTypePtr: {
                if (isHex || [input containsString:@"0x"]) {
                    unsigned long long hexValue;
                    NSString *hexStr = [input lowercaseString];
                    if ([hexStr hasPrefix:@"0x"]) {
                        hexStr = [hexStr substringFromIndex:2];
                    }
                    [[NSScanner scannerWithString:hexStr] scanHexLongLong:&hexValue];
                    valueToWrite = hexValue;
                } else {
                    valueToWrite = [input longLongValue];
                }
                break;
            }
        }
        
        kern_return_t kr = mach_vm_write(mach_task_self(), address, (vm_offset_t)&valueToWrite, sizeof(valueToWrite));
        
        mach_vm_size_t writeSize = 4;
        if (type == SearchDataTypeI64 || type == SearchDataTypeF64 || type == SearchDataTypePtr) {
            writeSize = 8;
        } else if (type == SearchDataTypeI16) {
            writeSize = 2;
        } else if (type == SearchDataTypeU8) {
            writeSize = 1;
        }
        
        kr = mach_vm_write(mach_task_self(), address, (vm_offset_t)&valueToWrite, writeSize);
        
        if (kr == KERN_SUCCESS) {
            [LoggingService log:@"数值修改成功: 0x%llX -> %@", address, input];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ModifyValueNotification"
                                                              object:nil
                                                            userInfo:@{
                @"address": @(address),
                @"newValue": input,
                @"type": @(type)
            }];
        } else {
            [LoggingService log:@"数值修改失败: 0x%llX (Error: %d)", address, kr];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    
    CGPoint location = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    if (!indexPath || indexPath.row >= self.dataSource.count) {
        return;
    }
    
    NSAttributedString *rowText = self.dataSource[indexPath.row];
    NSString *plainText = rowText.string;
    
    [LoggingService log:@"长按复制 - 原始文本: %@", plainText];
    
    NSArray *components = [plainText componentsSeparatedByString:@"    "];
    if (components.count == 0) {
        [LoggingService log:@"错误：无法解析文本"];
        return;
    }
    
    NSString *addressPart = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    NSScanner *scanner = [NSScanner scannerWithString:addressPart];
    uint64_t address;
    if (![scanner scanHexLongLong:&address]) {
        [LoggingService log:@"错误：无法解析地址: %@", addressPart];
        return;
    }
    
    NSString *addressString = [NSString stringWithFormat:@"0x%llX", address];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"复制地址"
                                                                   message:addressString
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"复制地址" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = addressString;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)modeSwitchChanged:(UISwitch *)sender {
    for (UIButton *button in self.searchModeButtons) {
        button.hidden = sender.isOn;
    }
    
    for (UIButton *button in self.editModeButtons) {
        button.hidden = !sender.isOn;
    }
    
    if (!sender.isOn) {
        [self.selectedIndexes removeAllObjects];
        [self.tableView reloadData];
    }
}

- (void)handleOffsetApplied:(NSNotification *)notification {
    int64_t offset = [notification.userInfo[@"offset"] longLongValue];
    [LoggingService log:@"处理地址偏移: %lld", offset];
    
    SearchDataType currentType = 当前数据类型;
    
    NSMutableArray *newAddresses = [NSMutableArray array];
    
    if (当前搜索模式 == 模式二) {
        [LoggingService log:@"模式二：开始处理结果文件数据"];
        
        FILE* fp = fopen(search_results->result_file_path, "rb");
        if (fp) {
            AddressValuePair pair;
            while (fread(&pair, sizeof(AddressValuePair), 1, fp) == 1) {
                uint64_t newAddress = pair.address + offset;
                [newAddresses addObject:@(newAddress)];
            }
            fclose(fp);
            
            if (newAddresses.count > 0) {
                char* new_result_path = 创建临时文件();
                if (new_result_path) {
                    FILE* new_fp = fopen(new_result_path, "wb");
                    if (new_fp) {
                        for (NSNumber* addr in newAddresses) {
                            uint64_t address = [addr unsignedLongLongValue];
                            uint64_t value;
                            mach_vm_size_t size = sizeof(uint64_t);
                            mach_vm_address_t targetAddress = address;
                            mach_vm_size_t outsize;
                            mach_vm_read_overwrite(mach_task_self(), targetAddress, size, (mach_vm_address_t)&value, &outsize);
                            AddressValuePair new_pair;
                            new_pair.address = address;
                            memcpy(new_pair.bytes, &value, sizeof(value));
                            fwrite(&new_pair, sizeof(AddressValuePair), 1, new_fp);
                        }
                        fclose(new_fp);
                        
                        删除临时文件(search_results->result_file_path);
                        free(search_results->result_file_path);
                        search_results->result_file_path = new_result_path;
                        search_results->count = newAddresses.count;
                    } else {
                        删除临时文件(new_result_path);
                        free(new_result_path);
                    }
                }
            }
        }
    }
    
    if (newAddresses.count > 0) {
        [LoggingService log:@"更新 %lu 个偏移后的地址", (unsigned long)newAddresses.count];
        [self updateSearchResults:newAddresses withType:currentType];
    } else {
        [LoggingService log:@"没有找到可以偏移的地址"];
    }
}

@end
