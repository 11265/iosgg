#import "Services/MemoryProcessor.h"
#import "Services/LogService.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import "Services/ProcessMemory.h"
#import "Services/LogService.h"

@implementation SSMemoryHandler

- (instancetype)initWithWebView:(WKWebView *)webView {
    self = [super init];
    if (self) {
        _webView = webView;
    }
    return self;
}

- (void)handleMemoryMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    NSString *action = data[@"action"];
    
    if ([action isEqualToString:@"refresh"]) {
        uint64_t baseAddr = strtoull([data[@"address"] UTF8String], NULL, 16);
        NSMutableArray *memoryData = [NSMutableArray array];
        
        // 读取从基址开始的一段内存
        for (int i = 0; i < 16; i++) {
            uint64_t currentAddr = baseAddr + i;
            uint8_t value = 0;
            mach_vm_size_t size = 1;
            
            // 读取目标进程内存
            kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), 
                                                     currentAddr, 
                                                     size,
                                                     (mach_vm_address_t)&value, 
                                                     &size);
            
            if (kr == KERN_SUCCESS) {
                [memoryData addObject:@{
                    @"address": [NSString stringWithFormat:@"0x%llX", currentAddr],
                    @"hex": [NSString stringWithFormat:@"0x%02X", value],
                    @"dec": [NSString stringWithFormat:@"%d", value]
                }];
            } else {
                // 读取失败时显示 -- 
                [memoryData addObject:@{
                    @"address": [NSString stringWithFormat:@"0x%llX", currentAddr],
                    @"hex": @"--",
                    @"dec": @"--"
                }];
            }
        }
        
        NSString *jsCode = [NSString stringWithFormat:@"updateMemoryData(%@)",
                           [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:memoryData options:0 error:nil]
                                               encoding:NSUTF8StringEncoding]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:jsCode completionHandler:nil];
        });
    } 
    else if ([action isEqualToString:@"parsePointer"]) {
        NSString *expression = data[@"expression"];
        uint64_t currentAddr = 0;
        
        // 首先检查是否是纯地址格式（以0x开头）
        if ([expression hasPrefix:@"0x"]) {
            // 检查是否包含偏移
            NSArray *components = [expression componentsSeparatedByString:@"+"];
            currentAddr = strtoull([components[0] UTF8String], NULL, 16);
            [LoggingService log:@"直接使用地址: 0x%llX", currentAddr];
            
            // 处理所有偏移
            for (NSUInteger i = 1; i < components.count; i++) {
                NSString *trimmedOffset = [components[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (![trimmedOffset hasPrefix:@"0x"]) {
                    trimmedOffset = [@"0x" stringByAppendingString:trimmedOffset];
                }
                uint64_t offset = strtoull([trimmedOffset UTF8String], NULL, 16);
                currentAddr += offset;
                [LoggingService log:@"添加偏移: 0x%llX, 最终地址: 0x%llX", offset, currentAddr];
            }
        } else {
            // 不是纯地址，尝试解析模块+偏移格式
            NSArray *allComponents = [expression componentsSeparatedByString:@"+"];
            NSString *firstComponent = allComponents[0];
            
            // 检查第一个组件是否是地址（以0x开头）
            if ([firstComponent hasPrefix:@"0x"]) {
                currentAddr = strtoull([firstComponent UTF8String], NULL, 16);
                [LoggingService log:@"使用基址: 0x%llX", currentAddr];
            } else {
                // 不是地址，视为模块名
                currentAddr = [self getModuleBase:firstComponent];
                [LoggingService log:@"使用模块 %@ 的基址: 0x%llX", firstComponent, currentAddr];
            }
            
            // 处理后续的偏移
            for (NSUInteger i = 1; i < allComponents.count; i++) {
                NSString *trimmedOffset = [allComponents[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                // 如果偏移不以0x开头，自动添加
                if (![trimmedOffset hasPrefix:@"0x"]) {
                    trimmedOffset = [@"0x" stringByAppendingString:trimmedOffset];
                }
                uint64_t offset = strtoull([trimmedOffset UTF8String], NULL, 16);
                currentAddr += offset;
                
                // 如果不是最后一个偏移，需要读取指针指向的地址
                if (i < allComponents.count - 1) {
                    uint64_t nextAddr = 0;
                    mach_vm_size_t size = sizeof(uint64_t);
                    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                                            currentAddr,
                                                            size,
                                                            (mach_vm_address_t)&nextAddr,
                                                            &size);
                    
                    if (kr != KERN_SUCCESS) {
                        [LoggingService log:@"读取地址 0x%llX 失败", currentAddr];
                        return;
                    }
                    
                    [LoggingService log:@"偏移: 0x%llX, 读取地址: 0x%llX -> 0x%llX", 
                          offset, currentAddr, nextAddr];
                    currentAddr = nextAddr;
                } else {
                    [LoggingService log:@"最终偏移: 0x%llX, 最终地址: 0x%llX", offset, currentAddr];
                }
            }
        }
        
        // 读取最终地址的 int32 值
        int32_t finalValue = 0;
        mach_vm_size_t size = sizeof(int32_t);
        kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                                currentAddr,
                                                size,
                                                (mach_vm_address_t)&finalValue,
                                                &size);
        
        if (kr == KERN_SUCCESS) {
            NSString *jsCode = [NSString stringWithFormat:@"document.getElementById('pointerResult').value = '%d'", 
                              finalValue];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.webView evaluateJavaScript:jsCode completionHandler:^(id result, NSError *error) {
                    if (error) {
                        [LoggingService log:@"JavaScript执行错误: %@", error];
                    }
                }];
            });
            
            [LoggingService log:@"读取值成功 - 地址: 0x%llX, 值: %d", 
                  currentAddr, finalValue];
        } else {
            [LoggingService log:@"读取最终地址 0x%llX 的值失败", currentAddr];
        }
    }
}

// 获取模块基址的方法
- (uint64_t)getModuleBase:(NSString *)moduleName {
    uint32_t count = _dyld_image_count();
    [LoggingService log:@"开始查找模块 %@, 共有 %d 个模块", moduleName, count];
    
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            NSString *imageName = [NSString stringWithUTF8String:name];
            NSString *shortName = [imageName lastPathComponent];
            
            if ([shortName.lowercaseString containsString:moduleName.lowercaseString]) {
                uint64_t baseAddress = (uint64_t)_dyld_get_image_header(i);
                uint64_t slide = (uint64_t)_dyld_get_image_vmaddr_slide(i);
                
                [LoggingService log:@"找到匹配模块: %@", shortName];
                [LoggingService log:@"实际加载基址: 0x%llX, ASLR偏移: 0x%llX", 
                      baseAddress, slide];
                
                return baseAddress;
            }
        }
    }
    
    [LoggingService log:@"未找到匹配的模块: %@", moduleName];
    return 0;
}

#pragma mark - WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message {
    [self handleMemoryMessage:message];
}

@end 