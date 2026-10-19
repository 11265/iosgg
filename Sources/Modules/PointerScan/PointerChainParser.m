#import "Modules/PointerScan/PointerChainParser.h"
#import "Core/Algorithms/SSPointerChainCore.h"
#import "Core/Memory/SSMemoryBridge.h"
#import <mach-o/dyld.h>
#import <string.h>
#import <stdbool.h>
#import "Services/LogService.h"

/*
 * Objective-C 适配层：只负责 NSArray/NSError 与 mach 读内存。
 * 表达式解析、步骤求值都在 Core/Algorithms/SSPointerChainCore.cpp（C++17）里，
 * 这样同一套算法可以在主机上做单元测试。
 */

static void SSChainLogToService(const char *message, void *context) {
    (void)context;
    if (message) {
        [LoggingService log:@"%s", message];
    }
}

static int SSChainReadFromTask(uint64_t address, uint64_t *value, void *context) {
    (void)context;
    size_t read = 0;
    if (!SSMemoryRead(address, value, sizeof(uint64_t), &read)) {
        return 1;
    }
    return read == sizeof(uint64_t) ? 0 : 1;
}

static void SSCopyModuleName(SSChainStep *step, NSString *module) {
    if (!step || !module) return;
    const char *utf8 = module.UTF8String;
    if (!utf8) return;
    strncpy(step->module, utf8, sizeof(step->module) - 1);
    step->module[sizeof(step->module) - 1] = '\0';
}

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

    SSChainStep steps[SS_CHAIN_MAX_STEPS];
    size_t count = 0;
    bool overflow = false;

    for (NSDictionary *step in chain) {
        NSString *type = step[@"type"];
        uint64_t offset = [step[@"offset"] unsignedLongLongValue];

        if (count >= (size_t)SS_CHAIN_MAX_STEPS) {
            overflow = true;
            break;
        }

        SSChainStep native = {0};
        if ([type isEqualToString:@"module"]) {
            native.type = SS_CHAIN_STEP_MODULE;
            native.offset = offset;
            SSCopyModuleName(&native, step[@"module"]);
        } else if ([type isEqualToString:@"address"]) {
            native.type = SS_CHAIN_STEP_ADDRESS;
            native.offset = offset;
        } else if ([type isEqualToString:@"pointer"]) {
            native.type = SS_CHAIN_STEP_POINTER;
            native.offset = offset;
        } else {
            continue;
        }
        steps[count++] = native;
    }

    if (overflow) {
        NSString *message = @"指针链过长（最多 64 步）";
        [LoggingService log:@"[指针链] 错误: %@", message];
        if (error) {
            *error = [NSError errorWithDomain:@"PointerChain"
                                         code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return 0;
    }

    int status = 0;
    char message[SS_CHAIN_ERROR_MAX] = {0};
    uint64_t result = ss_chain_resolve(steps, count, moduleBase,
                                       SSChainReadFromTask, SSChainLogToService, NULL,
                                       &status, message, sizeof(message));

    if (status != 0) {
        NSString *text = [NSString stringWithUTF8String:message] ?: @"指针链求值失败";
        [LoggingService log:@"[指针链] 错误: %@", text];
        if (error) {
            *error = [NSError errorWithDomain:@"PointerChain"
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: text}];
        }
        return 0;
    }

    return result;
}

+ (NSArray *)parseChainExpression:(NSString *)expression error:(NSError **)error {
    SSChainStep steps[SS_CHAIN_MAX_STEPS];
    int code = 0;
    char message[SS_CHAIN_ERROR_MAX] = {0};

    const size_t count = ss_chain_parse(expression.UTF8String, steps, SS_CHAIN_MAX_STEPS,
                                        SSChainLogToService, NULL,
                                        &code, message, sizeof(message));

    if (count == 0) {
        NSString *text = [NSString stringWithUTF8String:message] ?: @"表达式解析失败";
        if (error) {
            *error = [NSError errorWithDomain:@"PointerChain"
                                         code:(code != 0 ? code : -1)
                                     userInfo:@{NSLocalizedDescriptionKey: text}];
        }
        return nil;
    }

    NSMutableArray *chain = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        const SSChainStep *step = &steps[i];
        if (step->type == SS_CHAIN_STEP_MODULE) {
            NSString *module = [NSString stringWithUTF8String:step->module] ?: @"";
            [chain addObject:@{
                @"type": @"module",
                @"module": module,
                @"offset": @(step->offset)
            }];
        } else if (step->type == SS_CHAIN_STEP_ADDRESS) {
            [chain addObject:@{
                @"type": @"address",
                @"offset": @(step->offset)
            }];
        } else if (step->type == SS_CHAIN_STEP_POINTER) {
            [chain addObject:@{
                @"type": @"pointer",
                @"offset": @(step->offset)
            }];
        }
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

                [LoggingService log:@"[模块查找] 找到匹配模块: %@, 基址: 0x%llX, ASLR: 0x%llX",
                    shortName, baseAddress, slide];

                return baseAddress;
            }
        }
    }

    [LoggingService log:@"[模块查找] 未找到匹配的模块: %@", moduleName];
    return 0;
}

@end
