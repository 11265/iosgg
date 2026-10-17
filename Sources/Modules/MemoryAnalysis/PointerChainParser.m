#import "Modules/MemoryAnalysis/PointerChainParser.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import "Services/LogService.h"
#import "Modules/ProcessInfo/ProcessMemory.h"

@implementation PointerChainResolver

+ (uint64_t)resolvePointerChain:(NSArray *)chain 
                      moduleBase:(uint64_t)moduleBase
                           error:(NSError **)error {
    if (chain.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PointerChain" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"空指针链"}];
        }
        return 0;
    }
    
    uint64_t currentAddr = 0;
    
    for (NSInteger i = 0; i < chain.count; i++) {
        NSDictionary *step = chain[i];
        NSString *type = step[@"type"];
        uint64_t offset = [step[@"offset"] unsignedLongLongValue];
        
        if ([type isEqualToString:@"module"]) {
            currentAddr = moduleBase + offset;
            [LoggingService log:@"[指针链] 模块基址: 0x%llX + 偏移: 0x%llX = 0x%llX", moduleBase, offset, currentAddr];
        } 
        else if ([type isEqualToString:@"address"]) {
            currentAddr = offset;
            [LoggingService log:@"[指针链] 直接地址: 0x%llX", currentAddr];
        }
        else if ([type isEqualToString:@"pointer"]) {
            uint64_t pointerValue = 0;
            mach_vm_size_t size = sizeof(uint64_t);
            kern_return_t kr = mach_vm_read_overwrite(
                mach_task_self(), 
                currentAddr, 
                size, 
                (mach_vm_address_t)&pointerValue, 
                &size
            );
            
            if (kr != KERN_SUCCESS) {
                NSString *errorMsg = [NSString stringWithFormat:@"读取地址 0x%llX 失败 (错误码: %d)", currentAddr, kr];
                [LoggingService log:@"[指针链] 错误: %@", errorMsg];
                
                if (error) {
                    *error = [NSError errorWithDomain:@"PointerChain" 
                                                 code:kr 
                                             userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
                }
                return 0;
            }
            
            currentAddr = pointerValue + offset;
            [LoggingService log:@"[指针链] 读取指针: 0x%llX + 偏移: 0x%llX = 0x%llX", pointerValue, offset, currentAddr];
        }
    }
    
    [LoggingService log:@"[指针链] 最终地址: 0x%llX", currentAddr];
    return currentAddr;
}

+ (NSArray *)parseChainExpression:(NSString *)expression error:(NSError **)error {
    NSMutableArray *chain = [NSMutableArray array];
    
    NSString *trimmedExpression = [expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if (trimmedExpression.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PointerChain" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"表达式为空"}];
        }
        return nil;
    }
    
    // 检测分隔符类型
    NSString *delimiter = nil;
    if ([trimmedExpression containsString:@"->"]) {
        delimiter = @"->";
    } else if ([trimmedExpression containsString:@","]) {
        delimiter = @",";
    } else if ([trimmedExpression containsString:@";"]) {
        delimiter = @";";
    } else if ([trimmedExpression containsString:@"|"]) {
        delimiter = @"|";
    }
    
    // 格式1: 使用分隔符的指针链格式 [模块+偏移] 分隔符 +偏移 分隔符 +偏移
    if (delimiter) {
        NSArray *components = [trimmedExpression componentsSeparatedByString:delimiter];
        
        NSString *baseComponent = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        if ([baseComponent hasPrefix:@"["] && [baseComponent hasSuffix:@"]"]) {
            baseComponent = [baseComponent substringWithRange:NSMakeRange(1, baseComponent.length - 2)];
            
            NSArray *baseParts = [baseComponent componentsSeparatedByString:@"+"];
            
            if (baseParts.count >= 2) {
                NSString *moduleName = [[baseParts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
                NSString *offsetStr = [[baseParts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@" " withString:@""];
                uint64_t offset = strtoull([offsetStr UTF8String], NULL, 16);
                
                [chain addObject:@{
                    @"type": @"module",
                    @"module": moduleName,
                    @"offset": @(offset)
                }];
                
                [LoggingService log:@"[解析] 模块: %@, 偏移: 0x%llX", moduleName, offset];
            } else if (baseParts.count == 1) {
                NSString *moduleName = [[baseParts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
                
                [chain addObject:@{
                    @"type": @"module",
                    @"module": moduleName,
                    @"offset": @0
                }];
                
                [LoggingService log:@"[解析] 模块: %@ (无偏移)", moduleName];
            } else {
                if (error) {
                    *error = [NSError errorWithDomain:@"PointerChain" 
                                                 code:-2 
                                             userInfo:@{NSLocalizedDescriptionKey: @"基址格式错误: 应为 [模块 + 偏移]"}];
                }
                return nil;
            }
        } else {
            if (error) {
                *error = [NSError errorWithDomain:@"PointerChain" 
                                             code:-3 
                                         userInfo:@{NSLocalizedDescriptionKey: @"基址部分缺少 []"}];
            }
            return nil;
        }
        
        for (NSInteger i = 1; i < components.count; i++) {
            NSString *offsetStr = [components[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            offsetStr = [offsetStr stringByReplacingOccurrencesOfString:@"+" withString:@""];
            offsetStr = [offsetStr stringByReplacingOccurrencesOfString:@" " withString:@""];
            
            if (offsetStr.length == 0) {
                continue;
            }
            
            uint64_t offset = strtoull([offsetStr UTF8String], NULL, 16);
            
            [chain addObject:@{
                @"type": @"pointer",
                @"offset": @(offset)
            }];
            
            [LoggingService log:@"[解析] 指针偏移: 0x%llX", offset];
        }
    }
    // 格式2: [模块+偏移] 或 [模块] (单级模块地址)
    else if ([trimmedExpression hasPrefix:@"["] && [trimmedExpression hasSuffix:@"]"]) {
        NSString *innerContent = [trimmedExpression substringWithRange:NSMakeRange(1, trimmedExpression.length - 2)];
        innerContent = [innerContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        if ([innerContent containsString:@"+"]) {
            NSArray *parts = [innerContent componentsSeparatedByString:@"+"];
            
            if (parts.count >= 2) {
                NSString *moduleName = [[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
                NSString *offsetStr = [[parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@" " withString:@""];
                uint64_t offset = strtoull([offsetStr UTF8String], NULL, 16);
                
                [chain addObject:@{
                    @"type": @"module",
                    @"module": moduleName,
                    @"offset": @(offset)
                }];
                
                [LoggingService log:@"[解析] 模块地址: [%@ + 0x%llX]", moduleName, offset];
            } else {
                if (error) {
                    *error = [NSError errorWithDomain:@"PointerChain" 
                                                 code:-2 
                                             userInfo:@{NSLocalizedDescriptionKey: @"格式错误: 应为 [模块 + 偏移]"}];
                }
                return nil;
            }
        } else {
            NSString *moduleName = [innerContent lowercaseString];
            
            [chain addObject:@{
                @"type": @"module",
                @"module": moduleName,
                @"offset": @0
            }];
            
            [LoggingService log:@"[解析] 模块基址: [%@]", moduleName];
        }
    }
    // 格式3: 0x地址 + 偏移 + 偏移 (直接地址格式)
    else if ([trimmedExpression hasPrefix:@"0x"] || [trimmedExpression hasPrefix:@"0X"]) {
        NSArray *components = [trimmedExpression componentsSeparatedByString:@"+"];
        
        NSString *baseAddrStr = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        uint64_t baseAddr = strtoull([baseAddrStr UTF8String], NULL, 16);
        
        [chain addObject:@{
            @"type": @"address",
            @"offset": @(baseAddr)
        }];
        
        [LoggingService log:@"[解析] 基址: 0x%llX", baseAddr];
        
        for (NSInteger i = 1; i < components.count; i++) {
            NSString *offsetStr = [components[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            offsetStr = [offsetStr stringByReplacingOccurrencesOfString:@" " withString:@""];
            
            if (![offsetStr hasPrefix:@"0x"] && ![offsetStr hasPrefix:@"0X"]) {
                offsetStr = [@"0x" stringByAppendingString:offsetStr];
            }
            
            uint64_t offset = strtoull([offsetStr UTF8String], NULL, 16);
            
            [chain addObject:@{
                @"type": @"pointer",
                @"offset": @(offset)
            }];
            
            [LoggingService log:@"[解析] 指针偏移: 0x%llX", offset];
        }
    }
    // 格式4: 模块+偏移 或 模块 (无[]的模块格式)
    else if (![trimmedExpression hasPrefix:@"0x"] && ![trimmedExpression hasPrefix:@"0X"]) {
        if ([trimmedExpression containsString:@"+"]) {
            NSArray *parts = [trimmedExpression componentsSeparatedByString:@"+"];
            
            if (parts.count >= 2) {
                NSString *moduleName = [[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
                NSString *offsetStr = [[parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@" " withString:@""];
                
                if (![offsetStr hasPrefix:@"0x"] && ![offsetStr hasPrefix:@"0X"]) {
                    offsetStr = [@"0x" stringByAppendingString:offsetStr];
                }
                
                uint64_t offset = strtoull([offsetStr UTF8String], NULL, 16);
                
                [chain addObject:@{
                    @"type": @"module",
                    @"module": moduleName,
                    @"offset": @(offset)
                }];
                
                [LoggingService log:@"[解析] 模块地址: %@ + 0x%llX", moduleName, offset];
            } else {
                if (error) {
                    *error = [NSError errorWithDomain:@"PointerChain" 
                                                 code:-2 
                                             userInfo:@{NSLocalizedDescriptionKey: @"格式错误: 应为 模块 + 偏移"}];
                }
                return nil;
            }
        } else {
            NSString *moduleName = [trimmedExpression lowercaseString];
            
            [chain addObject:@{
                @"type": @"module",
                @"module": moduleName,
                @"offset": @0
            }];
            
            [LoggingService log:@"[解析] 模块基址: %@", moduleName];
        }
    }
    else {
        if (error) {
            *error = [NSError errorWithDomain:@"PointerChain" 
                                         code:-4 
                                     userInfo:@{NSLocalizedDescriptionKey: @"不支持的格式:\n支持的格式:\n• [模块+偏移], +偏移\n• [模块+偏移]\n• [模块]\n• 模块+偏移\n• 模块\n• 0x地址 + 偏移"}];
        }
        return nil;
    }
    
    if (chain.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PointerChain" 
                                         code:-5 
                                     userInfo:@{NSLocalizedDescriptionKey: @"解析结果为空"}];
        }
        return nil;
    }
    
    return chain;
}

+ (NSString *)formatChainToString:(NSArray *)chain {
    if (chain.count == 0) {
        return @"";
    }
    
    NSMutableString *result = [NSMutableString string];
    
    for (NSInteger i = 0; i < chain.count; i++) {
        NSDictionary *step = chain[i];
        NSString *type = step[@"type"];
        uint64_t offset = [step[@"offset"] unsignedLongLongValue];
        
        if ([type isEqualToString:@"module"]) {
            NSString *moduleName = step[@"module"] ?: @"unknown";
            if (offset > 0) {
                [result appendFormat:@"[%@ + 0x%llX]", moduleName, offset];
            } else {
                [result appendFormat:@"[%@]", moduleName];
            }
        } else if ([type isEqualToString:@"address"]) {
            [result appendFormat:@"0x%llX", offset];
        } else if ([type isEqualToString:@"pointer"]) {
            [result appendFormat:@", +0x%llX", offset];
        }
    }
    
    return result;
}

+ (uint64_t)getModuleBase:(NSString *)moduleName {
    if (!moduleName || moduleName.length == 0) {
        [LoggingService log:@"[模块查找] 模块名为空"];
        return 0;
    }
    
    NSString *lowercaseModuleName = moduleName.lowercaseString;
    uint32_t count = _dyld_image_count();
    
    [LoggingService log:@"[模块查找] 开始查找模块: %@, 共有 %d 个模块", moduleName, count];
    
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            NSString *imageName = [NSString stringWithUTF8String:name];
            NSString *shortName = [imageName lastPathComponent];
            
            if ([shortName.lowercaseString containsString:lowercaseModuleName]) {
                uint64_t baseAddress = (uint64_t)_dyld_get_image_header(i);
                uint64_t slide = (uint64_t)_dyld_get_image_vmaddr_slide(i);
                
                [LoggingService log:@"[模块查找] 找到匹配模块: %@, 基址: 0x%llX, ASLR: 0x%llX", shortName, baseAddress, slide];
                
                return baseAddress;
            }
        }
    }
    
    [LoggingService log:@"[模块查找] 未找到匹配的模块: %@", moduleName];
    return 0;
}

@end
