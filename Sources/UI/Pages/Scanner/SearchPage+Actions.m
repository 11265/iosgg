#import "UI/Pages/Scanner/SearchPage+Actions.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Dialogs/EditValueDialog.h"
#import "UI/Dialogs/CompareDialog.h"
#import "UI/Dialogs/OffsetDialog.h"
#import "UI/Dialogs/SignatureDialog.h"
#import "UI/Dialogs/SearchDialog.h"
#import "UI/Dialogs/FuzzySearchDialog.h"
#import "UI/Dialogs/RegisterStateDialog.h"
#import "UI/Pages/Debugger/TracePage.h"
#import "UI/Pages/Record/RecordPage.h"
#import "Services/LogService.h"
#import "Core/Memory/SSMemoryBridge.h"
#import "Modules/Scanner/Scanner.h"
#import "Models/SSRecordStore.h"
#import "Models/SSDataTypeUtility.h"

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
    
    NSMutableArray<SSMemoryRecord *> *toSave = [NSMutableArray array];
    for (NSNumber *index in self.selectedIndexes) {
        NSInteger row = index.integerValue;
        if (row >= self.dataSource.count) continue;
        SSMemoryRecord *rec = self.dataSource[row];
        
        // 拷贝一份存入记录库，避免与搜索结果集共享同一对象（结果集会随下次搜索重建）
        SSMemoryRecord *copy = [[SSMemoryRecord alloc] init];
        copy.address = rec.address;
        copy.type = rec.type;
        copy.lastValue = rec.lastValue;
        [toSave addObject:copy];
        [LoggingService log:@"搜索页面: 添加地址 %@ 类型 %@", rec.addressString, rec.typeString];
    }
    
    [[SSRecordStore sharedStore] addRecords:toSave];
    [LoggingService log:@"搜索页面: 已写入记录库 %lu 条（Store 自动去重并通知记录页）", (unsigned long)toSave.count];
    
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
    
    SSMemoryRecord *firstRec = self.dataSource[firstIndex];
    SSMemoryRecord *secondRec = self.dataSource[secondIndex];
    uint64_t firstAddress = firstRec.address;
    uint64_t secondAddress = secondRec.address;
    
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
        SSMemoryRecord *rec = self.dataSource[indexPath.row];
        [LoggingService log:@"点击感叹号 - 地址: 0x%llX, 类型: %d", (unsigned long long)rec.address, (int)rec.type];
        [self showModifyAlertForAddress:rec.address type:rec.type];
    }
}

- (void)showModifyAlertForAddress:(uint64_t)address type:(SearchDataType)type {
    uint64_t currentValue = 0;
    size_t readWidth = [SSDataTypeUtility widthForType:type];
    size_t outsize = 0;
    SSMemoryRead(address, &currentValue, readWidth, &outsize);
    
    NSString *currentValueStr = [SSDataTypeUtility decimalStringForValue:currentValue type:type];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改数值"
                                                                 message:[NSString stringWithFormat:@"地址: 0x%llX", (unsigned long long)address]
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
        
        uint64_t valueToWrite = [SSDataTypeUtility rawValueFromInput:input type:type];
        size_t writeSize = [SSDataTypeUtility widthForType:type];
        const bool writeOK = SSMemoryWrite(address, &valueToWrite, writeSize, NULL);
        
        if (writeOK) {
            [LoggingService log:@"数值修改成功: 0x%llX -> %@", address, input];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ModifyValueNotification"
                                                              object:nil
                                                            userInfo:@{
                @"address": @(address),
                @"newValue": input,
                @"type": @(type)
            }];
        } else {
            [LoggingService log:@"数值修改失败: 0x%llX", address];
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
    
    SSMemoryRecord *rec = self.dataSource[indexPath.row];
    NSString *addressString = rec.addressString;
    
    [LoggingService log:@"长按复制 - 地址: %@", addressString];
    
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
    size_t 偏移后总数 = 0;   // 结果集真实条数（newAddresses 只保留前 2000 条给 UI）
    
    if (当前搜索模式 == 模式二) {
        [LoggingService log:@"模式二：开始处理结果文件数据"];
        
        FILE* fp = NULL;
        if (search_results && search_results->result_file_path) {
            fp = fopen(search_results->result_file_path, "rb");
        } else {
            [LoggingService log:@"偏移应用失败：当前没有结果集"];
        }
        if (fp) {
            char* new_result_path = 创建临时文件();
            FILE* new_fp = new_result_path ? fopen(new_result_path, "wb") : NULL;
            if (new_fp) {
                // 一遍扫描同时做两件事：写新的结果文件、只收集前 2000 条地址给 UI。
                // 旧实现把全部地址装进 NSMutableArray，百万级结果会在主线程直接卡死。
                AddressValuePair pair;
                size_t 总数 = 0;
                while (fread(&pair, sizeof(AddressValuePair), 1, fp) == 1) {
                    uint64_t address = pair.address + offset;
                    uint64_t value = 0;
                    size_t outsize = 0;
                    SSMemoryRead(address, &value, sizeof(uint64_t), &outsize);
                    AddressValuePair new_pair;
                    new_pair.address = address;
                    memcpy(new_pair.bytes, &value, sizeof(value));
                    if (fwrite(&new_pair, sizeof(AddressValuePair), 1, new_fp) == 1) 总数++;
                    if (newAddresses.count < 2000) [newAddresses addObject:@(address)];
                }
                fclose(new_fp);
                new_fp = NULL;
                fclose(fp);
                fp = NULL;
                
                if (总数 > 0) {
                    删除临时文件(search_results->result_file_path);
                    free(search_results->result_file_path);
                    search_results->result_file_path = new_result_path;
                    search_results->count = 总数;
                    偏移后总数 = 总数;
                    [LoggingService log:@"偏移完成，共 %zu 条（回传 UI %lu 条）", 总数, (unsigned long)newAddresses.count];
                } else {
                    删除临时文件(new_result_path);
                    free(new_result_path);
                }
            } else if (new_result_path) {
                删除临时文件(new_result_path);
                free(new_result_path);
            }
            if (fp) fclose(fp);
        }
    }
    
    if (newAddresses.count > 0) {
        [LoggingService log:@"更新 %lu 个偏移后的地址（共 %zu 条）", (unsigned long)newAddresses.count, 偏移后总数];
        [self updateSearchResults:newAddresses
                       totalCount:(偏移后总数 > 0 ? 偏移后总数 : newAddresses.count)
                         withType:currentType];
    } else {
        [LoggingService log:@"没有找到可以偏移的地址"];
    }
}

@end
