#import "Services/Memory/InstructionBrowser.h"
#import "Services/LogService.h"
#import <mach/vm_map.h>
#import "Services/ProcessMemory.h"
#import "Services/Memory/ARM64Assembler.h"

@implementation InstructionBrowser

- (instancetype)init {
    self = [super init];
    if (self) {
        _task = MACH_PORT_NULL;
        _isLoading = NO;
    }
    return self;
}

- (BOOL)attachToSelf {
    if (_task != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), _task);
        _task = MACH_PORT_NULL;
    }
    
    _task = mach_task_self();
    
    if (_task == MACH_PORT_NULL) {
        return NO;
    }
    
    return YES;
}

- (uint64_t)readMemoryAtAddress:(uint64_t)address size:(size_t)size error:(NSError **)error {
    if (_task == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"InstructionBrowser" 
                                       code:-1 
                                   userInfo:@{NSLocalizedDescriptionKey: @"未附加到进程"}];
        }
        return 0;
    }
    
    uint64_t value = 0;
    mach_vm_size_t outsize = 0;
    kern_return_t kr = mach_vm_read_overwrite(_task, address, size, (mach_vm_address_t)&value, &outsize);
    
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"InstructionBrowser"
                                       code:kr
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"读取内存失败: %s", mach_error_string(kr)]}];
        }
        return 0;
    }
    
    if (size < 8) {
        value &= ((1ULL << (size * 8)) - 1);
    }
    
    return value;
}

- (NSString *)disassembleInstruction:(uint32_t)instruction atAddress:(uint64_t)address {
    // 使用ARM64Assembler来进行反汇编
    NSString *result = [ARM64Assembler disassembleInstruction:instruction atAddress:address];
    
    // 如果返回的是.word格式,说明是未识别的指令,记录日志
    if ([result hasPrefix:@".word"]) {
        [LoggingService log:@"未识别的指令: 0x%08x at 0x%llx", instruction, address];
    }
    
    return result;
}

@end 