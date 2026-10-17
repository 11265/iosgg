#import "UI/Pages/Memory/MemoryPage+AssemblyActions.h"
#import "UI/Pages/Memory/MemoryPage+Private.h"
#import "UI/Components/ThemeConfig.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Dialogs/OptionsMenu.h"
#import "UI/Pages/Record/RecordPage.h"
#import "Modules/MemoryAnalysis/AIAnalysisService.h"
#import "Modules/MemoryAnalysis/ARM64Assembler.h"
#import "Modules/MemoryAnalysis/InstructionBrowser.h"
#import "Models/DisplayItem.h"
#import "Services/LogService.h"
#import "Modules/Debugger/SSDebugger.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/dyld_images.h>
@implementation MemoryPages (AssemblyActions)

- (uint32_t)assembleInstruction:(NSString *)instructionStr atAddress:(uint64_t)address {
    return [ARM64Assembler assembleInstruction:instructionStr atAddress:address];
}

- (NSString *)generatePattern:(uint32_t)instruction withDisassembly:(NSString *)disassembly atAddress:(uint64_t)address {
    NSMutableString *pattern = [NSMutableString string];
    NSError *error = nil;
    uint8_t *bytes = malloc(self.patternLength);
    
    for (int i = 0; i < self.patternLength; i++) {
        uint64_t currentAddress = address + i;
        uint8_t byte = (uint8_t)[self.instructionBrowser readMemoryAtAddress:currentAddress size:1 error:&error];
        if (error) {
            free(bytes);
            return @"读取内存失败";
        }
        bytes[i] = byte;
    }
    
    for (int i = 0; i < self.patternLength; i++) {
        [pattern appendFormat:@"%02X", bytes[i]];
        if (i < self.patternLength - 1) {
            [pattern appendString:@" "];
        }
    }
    
    free(bytes);
    return pattern;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint point = [gestureRecognizer locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
        
        if (indexPath && self.selectedTypeIndex == 4) {
            if (indexPath.row >= self.displayItems.count) return;
            DisplayItem *item = self.displayItems[indexPath.row];
            uint64_t address = item.instruction.address;
            uint32_t instruction = item.instruction.value;
            
            NSString *disassembly = [NSString stringWithFormat:@"%@ %@", item.instruction.mnemonic, item.instruction.opStr];
            
            SSDebugger *debugger = [SSDebugger sharedInstance];
            BOOL hasBreakpoint = [debugger hasFunctionBreakpointAtAddress:address];
            
            NSMutableArray *options = [NSMutableArray arrayWithArray:
                @[@"生成特征码", @"计算偏移", @"复制指令", @"复制地址", @"AI 分析"]];
            if (hasBreakpoint) {
                [options addObject:@"移除执行断点"];
            } else {
                [options addObject:@"设执行断点(软件)"];
                [options addObject:@"设执行断点(硬件)"];
                [options addObject:@"设执行断点(软件·命中不停顿)"];
            }
            SSCustomMenuView *menuView = [[SSCustomMenuView alloc] initWithOptions:options];
            
            __weak typeof(self) weakSelf = self;
            menuView.onOptionSelected = ^(NSInteger index) {
                switch (index) {
                    case 0: [weakSelf handleGeneratePattern:address instruction:instruction disassembly:disassembly]; break;
                    case 1: [weakSelf handleCalculateOffset:address]; break;
                    case 2: [UIPasteboard generalPasteboard].string = disassembly; break;
                    case 3: [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"0x%llX", address]; break;
                    case 4: [weakSelf handleAIAnalysis:address instruction:instruction disassembly:disassembly]; break;
                    case 5:
                        if (hasBreakpoint) {
                            [weakSelf removeExecuteBreakpoint:address];
                        } else {
                            [weakSelf addExecuteBreakpoint:address software:YES stopExecution:YES];
                        }
                        break;
                    case 6: [weakSelf addExecuteBreakpoint:address software:NO stopExecution:YES]; break;
                    case 7: [weakSelf addExecuteBreakpoint:address software:YES stopExecution:NO]; break;
                }
            };
            [menuView showFromPoint:point inView:self.view];
        }
    }
}

- (void)addExecuteBreakpoint:(uint64_t)address software:(BOOL)software stopExecution:(BOOL)stopExecution {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    pid_t pid = (pid_t)[NSProcessInfo processInfo].processIdentifier;
    
    if (!debugger.isDebugging) {
        [LoggingService log:@"[断点] 调试器未运行，先启动 (pid=%d)", pid];
        if (![debugger startDebugWithPid:pid]) {
            [self showBreakpointAlert:@"启动调试器失败，无法下断点"];
            return;
        }
    }
    
    debugger.breakpointStopsExecution = stopExecution;
    
    if (![debugger setFunctionBreakpoint:address software:software hitCount:0]) {
        [self showBreakpointAlert:[NSString stringWithFormat:
            @"下断点失败: 0x%llX\n%@",
            address,
            software ? @"代码页可能不可写（iOS 上通常需要 VM_PROT_COPY 才允许改代码段）；可以先试硬件断点"
                     : @"硬件断点槽位已满（ARM64 通常只有 4 个，且新建线程不会继承）"]];
        return;
    }
    
    [self showBreakpointAlert:[NSString stringWithFormat:
        @"已下%@执行断点\n地址: 0x%llX\n命中后：%@",
        software ? @"软件" : @"硬件",
        address,
        stopExecution ? @"暂停线程并弹出寄存器 + 调用栈（页面左上角有「继续」）"
                      : @"不暂停，只发通知（适合每帧都被调用的高频函数）"]];
}

- (void)removeExecuteBreakpoint:(uint64_t)address {
    [[SSDebugger sharedInstance] removeFunctionBreakpoint:address];
    [self showBreakpointAlert:[NSString stringWithFormat:@"已移除执行断点: 0x%llX", address]];
}

- (void)showBreakpointAlert:(NSString *)message {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"执行断点"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleAIAnalysis:(uint64_t)address instruction:(uint32_t)instruction disassembly:(NSString *)disassembly {
    // Collect context (surrounding instructions)
    NSMutableString *context = [NSMutableString string];
    [context appendString:@"Surrounding Assembly:\n"];
    
    // Find index of current instruction in displayItems if possible
    NSInteger currentIndex = -1;
    for (NSInteger i = 0; i < self.displayItems.count; i++) {
        if (self.displayItems[i].instruction.address == address) {
            currentIndex = i;
            break;
        }
    }
    
    if (currentIndex != -1) {
        NSInteger start = MAX(0, currentIndex - 5);
        NSInteger end = MIN((NSInteger)self.displayItems.count - 1, currentIndex + 5);
        
        for (NSInteger i = start; i <= end; i++) {
            DisplayItem *item = self.displayItems[i];
            NSString *prefix = (i == currentIndex) ? @"> " : @"  ";
            NSString *instrStr;
            if ([item.instruction.mnemonic isEqualToString:@".word"]) {
                instrStr = [NSString stringWithFormat:@".word 0x%08x", item.instruction.value];
            } else {
                instrStr = [NSString stringWithFormat:@"%@ %@", item.instruction.mnemonic, item.instruction.opStr];
            }
            [context appendFormat:@"%@0x%llX: %@\n", prefix, item.instruction.address, instrStr];
        }
    } else {
        [context appendFormat:@"0x%llX: %@\n", address, disassembly];
    }
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"AI 分析中..." message:@"正在请求分析..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    [[AIAnalysisService sharedInstance] analyzeAssembly:disassembly context:context completion:^(NSString * _Nullable analysis, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"分析失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                    
                    // Allow user to set API Key if it's missing
                    if (error.code == -1) { // "Please set API Key" code I used in service
                        [errAlert addAction:[UIAlertAction actionWithTitle:@"设置 API Key" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            [self showAPIKeyConfigDialog];
                        }]];
                    }
                    
                    [errAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:errAlert animated:YES completion:nil];
                } else {
                    // Show result
                    SSPatternResultView *resultView = [[SSPatternResultView alloc] initWithPattern:analysis]; // Reuse this view for now
                    resultView.delegate = self;
                    // Hack: Change title
                    UILabel *titleLabel = [resultView valueForKey:@"titleLabel"]; // Assuming it has one or just rely on content
                    if (titleLabel) titleLabel.text = @"AI 分析结果";
                    [resultView showInView:self.view];
                }
            }];
        });
    }];
}

- (void)showAPIKeyConfigDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AI 配置" message:@"请输入 OpenAI 格式的 API Key 和 Base URL" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"API Key (sk-...)";
        textField.secureTextEntry = YES;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Base URL (Default: https://api.openai.com/v1)";
        textField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"AIAnalysisBaseURL"];
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Model (Default: gpt-3.5-turbo)";
        textField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"AIAnalysisModel"];
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *apiKey = alert.textFields[0].text;
        NSString *baseURL = alert.textFields[1].text;
        NSString *model = alert.textFields[2].text;
        
        if (apiKey.length > 0) {
            [[AIAnalysisService sharedInstance] setApiKey:apiKey];
        }
        if (baseURL.length > 0) {
            [[AIAnalysisService sharedInstance] setBaseURL:baseURL];
        }
        if (model.length > 0) {
            [[AIAnalysisService sharedInstance] setModel:model];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleGeneratePattern:(uint64_t)address instruction:(uint32_t)instruction disassembly:(NSString *)disassembly {
    SSPatternLengthView *lengthView = [[SSPatternLengthView alloc] initWithAddress:address instruction:instruction disassembly:disassembly];
    lengthView.delegate = self;
    [lengthView showInView:self.view];
}

- (void)patternLengthView:(SSPatternLengthView *)view didConfirmWithLength:(NSInteger)length address:(uint64_t)address instruction:(uint32_t)instruction disassembly:(NSString *)disassembly {
    self.patternLength = length;
    NSString *pattern = [self generatePattern:instruction withDisassembly:disassembly atAddress:address];
    SSPatternResultView *resultView = [[SSPatternResultView alloc] initWithPattern:pattern];
    resultView.delegate = self;
    [resultView showInView:self.view];
}

- (void)patternResultViewDidCopy:(SSPatternResultView *)view {
    [UIPasteboard generalPasteboard].string = view.patternTextView.text;
}

- (void)patternResultViewDidConfirm:(SSPatternResultView *)view {
}

- (void)handleCalculateOffset:(uint64_t)address {
    SSOffsetCalculatorView *calculatorView = [[SSOffsetCalculatorView alloc] initWithAddress:address];
    calculatorView.delegate = self;
    [calculatorView showInView:self.view];
}

- (void)offsetCalculatorView:(SSOffsetCalculatorView *)view didConfirmWithModuleName:(NSString *)moduleName {
    uint64_t baseAddress = [self getModuleBaseAddress:moduleName];
    if (baseAddress == 0) return;
    
    long long offset = view.address - baseAddress;
    NSString *offsetStr = [NSString stringWithFormat:@"0x%llX", (uint64_t)llabs(offset)];
    
    SSOffsetResultView *resultView = [[SSOffsetResultView alloc] initWithOffset:offsetStr];
    resultView.delegate = self;
    [resultView showInView:self.view];
}

- (void)offsetResultViewDidCopy:(SSOffsetResultView *)view {
    [UIPasteboard generalPasteboard].string = view.offsetTextView.text;
}

- (void)offsetResultViewDidConfirm:(SSOffsetResultView *)view {
}

- (uint64_t)getModuleBaseAddress:(NSString *)moduleName {
    uint32_t count = _dyld_image_count();
    for(uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            NSString *imageName = [NSString stringWithUTF8String:name];
            if ([[imageName lastPathComponent] isEqualToString:moduleName]) {
                return (uint64_t)_dyld_get_image_header(i);
            }
        }
    }
    return 0;
}

- (void)instructionEditView:(SSInstructionEditView *)view didConfirmWithInstruction:(NSString *)newInstruction address:(uint64_t)address {
    if (newInstruction.length == 0) return;
    
    uint32_t newMachineCode = [ARM64Assembler assembleInstruction:newInstruction atAddress:address];
    vm_size_t pageSize = getpagesize();
    vm_address_t pageAddress = address & ~(pageSize - 1);
    vm_size_t pageCount = ((address + sizeof(uint32_t) - pageAddress) + pageSize - 1) & ~(pageSize - 1);
    
    kern_return_t kret = mach_vm_protect(self.instructionBrowser.task, pageAddress, pageCount, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE | VM_PROT_COPY);
    
    if (kret == KERN_SUCCESS) {
        kret = mach_vm_write(self.instructionBrowser.task, address, (vm_offset_t)&newMachineCode, sizeof(uint32_t));
        if (kret == KERN_SUCCESS) {
            mach_vm_protect(self.instructionBrowser.task, pageAddress, pageCount, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:150 + ((address - self.baseAddress) / 4) inSection:0];
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

@end
