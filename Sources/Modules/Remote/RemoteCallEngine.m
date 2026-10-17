#import "Modules/Remote/RemoteCallEngine.h"
#import "Services/LogService.h"
#import "Modules/ProcessInfo/ProcessMemory.h"
#import <pthread.h>

@implementation RemoteCallEngine

+ (instancetype)sharedInstance {
    static RemoteCallEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (uint64_t)callFunctionAtAddress:(uint64_t)address
                        parameters:(NSArray<NSNumber *> *)params
                       paramCount:(NSInteger)count
                             error:(NSError **)error {
    
    if (g_task_port == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无效的task port"}];
        }
        [LoggingService log:@"[远程调用] 错误: 无效的task port"];
        return 0;
    }
    
    if (g_task_port == mach_task_self()) {
        [LoggingService log:@"[远程调用] 检测到同一进程，使用直接调用"];
        
        typedef uint64_t (*func_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
        func_t func = (func_t)address;
        
        uint64_t args[8] = {0};
        for (int i = 0; i < count && i < 8; i++) {
            args[i] = [params[i] unsignedLongLongValue];
            [LoggingService log:@"[远程调用] 参数X%d = 0x%llX", i, args[i]];
        }
        
        uint64_t result = func(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
        [LoggingService log:@"[远程调用] 直接调用完成，返回值: 0x%llX", result];
        
        if (error) *error = nil;
        return result;
    }
    
    [LoggingService log:@"[远程调用] 开始调用函数: 0x%llX, 参数数量: %ld", address, (long)count];
    
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t thread_count = 0;
    kern_return_t kr;
    
    kr = task_threads(g_task_port, &threads, &thread_count);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法获取线程列表"}];
        }
        [LoggingService log:@"[远程调用] 错误: 无法获取线程列表, kr=%d", kr];
        return 0;
    }
    
    [LoggingService log:@"[远程调用] 找到 %d 个线程", thread_count];
    
    thread_t target_thread = threads[0];
    
    arm_thread_state64_t state;
    mach_msg_type_number_t state_count = ARM_THREAD_STATE64_COUNT;
    
    kr = thread_get_state(target_thread, ARM_THREAD_STATE64, (thread_state_t)&state, &state_count);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法获取线程状态"}];
        }
        [LoggingService log:@"[远程调用] 错误: 无法获取线程状态, kr=%d", kr];
        vm_deallocate(mach_task_self(), (vm_address_t)threads, thread_count * sizeof(thread_t));
        return 0;
    }
    
    uint64_t original_pc = state.__pc;
    uint64_t original_lr = state.__lr;
    uint64_t original_x0 = state.__x[0];
    uint64_t original_x1 = state.__x[1];
    uint64_t original_x2 = state.__x[2];
    uint64_t original_x3 = state.__x[3];
    uint64_t original_x4 = state.__x[4];
    uint64_t original_x5 = state.__x[5];
    uint64_t original_x6 = state.__x[6];
    uint64_t original_x7 = state.__x[7];
    
    [LoggingService log:@"[远程调用] 原始PC: 0x%llX, LR: 0x%llX", original_pc, original_lr];
    
    mach_vm_address_t shellcode_addr = 0;
    size_t shellcode_size = 0x1000;
    
    kr = mach_vm_allocate(g_task_port, &shellcode_addr, shellcode_size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法分配内存"}];
        }
        [LoggingService log:@"[远程调用] 错误: 无法分配内存, kr=%d", kr];
        vm_deallocate(mach_task_self(), (vm_address_t)threads, thread_count * sizeof(thread_t));
        return 0;
    }
    
    [LoggingService log:@"[远程调用] 分配shellcode内存: 0x%llX", shellcode_addr];
    
    uint32_t shellcode[64];
    int idx = 0;
    
    shellcode[idx++] = 0xA9BF7BFD;  // STP X29, X30, [SP, #-16]!
    shellcode[idx++] = 0xA9BF53F3;  // STP X19, X20, [SP, #-16]!
    shellcode[idx++] = 0xA9BF5BF5;  // STP X21, X22, [SP, #-16]!
    shellcode[idx++] = 0xA9BF63F7;  // STP X23, X24, [SP, #-16]!
    
    for (int i = 0; i < count && i < 8; i++) {
        uint64_t param_value = [params[i] unsignedLongLongValue];
        state.__x[i] = param_value;
        [LoggingService log:@"[远程调用] 设置X%d = 0x%llX", i, param_value];
    }
    
    state.__lr = original_pc;
    [LoggingService log:@"[远程调用] 设置LR = 0x%llX (原始PC)", original_pc];
    
    uint32_t imm16;
    imm16 = (uint32_t)(address & 0xFFFF);
    shellcode[idx++] = 0xD2800000 | (imm16 << 5) | 16;  // MOVZ X16, #imm16
    
    imm16 = (uint32_t)((address >> 16) & 0xFFFF);
    if (imm16 != 0) {
        shellcode[idx++] = 0xF2A00000 | (imm16 << 5) | 16;  // MOVK X16, #imm16, LSL #16
    }
    
    imm16 = (uint32_t)((address >> 32) & 0xFFFF);
    if (imm16 != 0) {
        shellcode[idx++] = 0xF2C00000 | (imm16 << 5) | 16;  // MOVK X16, #imm16, LSL #32
    }
    
    imm16 = (uint32_t)((address >> 48) & 0xFFFF);
    if (imm16 != 0) {
        shellcode[idx++] = 0xF2E00000 | (imm16 << 5) | 16;  // MOVK X16, #imm16, LSL #48
    }
    
    shellcode[idx++] = 0xD63F0200;  // BLR X16 (调用X16寄存器中的地址)
    
    [LoggingService log:@"[远程调用] 使用BLR X16调用地址: 0x%llX", address];
    
    shellcode[idx++] = 0xA9BF07E0;  // STP X0, X1, [SP, #-16]!
    
    for (int i = 0; i < 100; i++) {
        shellcode[idx++] = 0xD503201F;  // NOP
    }
    
    shellcode[idx++] = 0xA8C107E0;  // LDP X0, X1, [SP], #16
    
    shellcode[idx++] = 0xA8C163F7;  // LDP X23, X24, [SP], #16
    shellcode[idx++] = 0xA8C15BF5;  // LDP X21, X22, [SP], #16
    shellcode[idx++] = 0xA8C153F3;  // LDP X19, X20, [SP], #16
    shellcode[idx++] = 0xA8C17BFD;  // LDP X29, X30, [SP], #16
    
    shellcode[idx++] = 0xD65F03C0;  // RET (返回到LR，即原始PC)
    
    [LoggingService log:@"[远程调用] Shellcode使用RET指令返回到原始PC"];
    
    kr = mach_vm_write(g_task_port, shellcode_addr, (vm_offset_t)shellcode, idx * 4);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法写入shellcode, kr=%d", kr];
        mach_vm_deallocate(g_task_port, shellcode_addr, shellcode_size);
        vm_deallocate(mach_task_self(), (vm_address_t)threads, thread_count * sizeof(thread_t));
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法写入shellcode"}];
        }
        return 0;
    }
    
    kr = mach_vm_protect(g_task_port, shellcode_addr, shellcode_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法设置内存保护, kr=%d", kr];
        mach_vm_deallocate(g_task_port, shellcode_addr, shellcode_size);
        vm_deallocate(mach_task_self(), (vm_address_t)threads, thread_count * sizeof(thread_t));
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法设置内存保护"}];
        }
        return 0;
    }
    
    [LoggingService log:@"[远程调用] Shellcode已写入并设置为可执行"];
    
    state.__pc = shellcode_addr;
    
    kr = thread_set_state(target_thread, ARM_THREAD_STATE64, (thread_state_t)&state, ARM_THREAD_STATE64_COUNT);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法设置线程状态, kr=%d", kr];
        mach_vm_deallocate(g_task_port, shellcode_addr, shellcode_size);
        vm_deallocate(mach_task_self(), (vm_address_t)threads, thread_count * sizeof(thread_t));
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法设置线程状态"}];
        }
        return 0;
    }
    
    [LoggingService log:@"[远程调用] 线程状态已设置，PC=0x%llX", state.__pc];
    
    kr = thread_resume(target_thread);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法恢复线程, kr=%d", kr];
    }
    
    [NSThread sleepForTimeInterval:0.1];
    
    kr = thread_suspend(target_thread);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法暂停线程, kr=%d", kr];
    }
    
    kr = thread_get_state(target_thread, ARM_THREAD_STATE64, (thread_state_t)&state, &state_count);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法获取线程状态, kr=%d", kr];
    }
    
    uint64_t return_value = state.__x[0];
    [LoggingService log:@"[远程调用] 返回值: 0x%llX", return_value];
    
    state.__pc = original_pc;
    state.__lr = original_lr;
    state.__x[0] = original_x0;
    state.__x[1] = original_x1;
    state.__x[2] = original_x2;
    state.__x[3] = original_x3;
    state.__x[4] = original_x4;
    state.__x[5] = original_x5;
    state.__x[6] = original_x6;
    state.__x[7] = original_x7;
    
    kr = thread_set_state(target_thread, ARM_THREAD_STATE64, (thread_state_t)&state, ARM_THREAD_STATE64_COUNT);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法恢复线程状态, kr=%d", kr];
    }
    
    kr = thread_resume(target_thread);
    if (kr != KERN_SUCCESS) {
        [LoggingService log:@"[远程调用] 错误: 无法恢复线程, kr=%d", kr];
    }
    
    mach_vm_deallocate(g_task_port, shellcode_addr, shellcode_size);
    vm_deallocate(mach_task_self(), (vm_address_t)threads, thread_count * sizeof(thread_t));
    
    [LoggingService log:@"[远程调用] 调用完成，返回值: 0x%llX", return_value];
    
    if (error) *error = nil;
    return return_value;
}

- (BOOL)callFunctionAtAddress:(uint64_t)address
                    parameters:(NSArray<NSNumber *> *)params
                   paramCount:(NSInteger)count
                   completion:(RemoteCallCompletionBlock)completion {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *error = nil;
        uint64_t returnValue = [self callFunctionAtAddress:address
                                                 parameters:params
                                                paramCount:count
                                                      error:&error];
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(returnValue, error);
            });
        }
    });
    
    return YES;
}

- (BOOL)allocateMemoryInTarget:(size_t)size
                       address:(mach_vm_address_t *)address
                         error:(NSError **)error {
    
    if (g_task_port == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无效的task port"}];
        }
        return NO;
    }
    
    kern_return_t kr = mach_vm_allocate(g_task_port, address, size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法分配内存"}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)writeMemoryAtAddress:(mach_vm_address_t)address
                     data:(const void *)data
                     size:(size_t)size
                    error:(NSError **)error {
    
    if (g_task_port == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无效的task port"}];
        }
        return NO;
    }
    
    kern_return_t kr = mach_vm_write(g_task_port, address, (vm_offset_t)data, (mach_msg_type_number_t)size);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法写入内存"}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)readMemoryAtAddress:(mach_vm_address_t)address
                    data:(void *)data
                    size:(size_t)size
                   error:(NSError **)error {
    
    if (g_task_port == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无效的task port"}];
        }
        return NO;
    }
    
    mach_vm_size_t outsize = 0;
    kern_return_t kr = mach_vm_read_overwrite(g_task_port, address, size, (mach_vm_address_t)data, &outsize);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法读取内存"}];
        }
        return NO;
    }
    
    return YES;
}

- (uint64_t)testMemoryCall:(NSError **)error {
    [LoggingService log:@"[测试] 开始内存call测试"];
    
    if (g_task_port == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无效的task port"}];
        }
        return 0;
    }
    
    mach_vm_address_t test_addr = 0;
    size_t test_size = 0x1000;
    
    kern_return_t kr = mach_vm_allocate(g_task_port, &test_addr, test_size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法分配测试内存"}];
        }
        [LoggingService log:@"[测试] 错误: 无法分配内存"];
        return 0;
    }
    
    [LoggingService log:@"[测试] 分配测试内存: 0x%llX", test_addr];
    
    uint32_t test_code[] = {
        0xD2800000,  // MOV X0, #0x0
        0xD65F03C0,  // RET
    };
    
    test_code[0] = 0xD2800000 | (0x1234 << 5);
    
    kr = mach_vm_write(g_task_port, test_addr, (vm_offset_t)test_code, sizeof(test_code));
    if (kr != KERN_SUCCESS) {
        mach_vm_deallocate(g_task_port, test_addr, test_size);
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法写入测试代码"}];
        }
        [LoggingService log:@"[测试] 错误: 无法写入代码"];
        return 0;
    }
    
    kr = mach_vm_protect(g_task_port, test_addr, test_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        mach_vm_deallocate(g_task_port, test_addr, test_size);
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法设置内存保护"}];
        }
        [LoggingService log:@"[测试] 错误: 无法设置内存保护"];
        return 0;
    }
    
    [LoggingService log:@"[测试] 测试代码已写入: MOV X0, #0x1234; RET"];
    
    uint64_t result = [self callFunctionAtAddress:test_addr parameters:@[] paramCount:0 error:error];
    
    [LoggingService log:@"[测试] 调用结果: 0x%llX (期望: 0x1234)", result];
    
    mach_vm_deallocate(g_task_port, test_addr, test_size);
    
    if (result == 0x1234) {
        [LoggingService log:@"[测试] 测试成功！"];
        if (error) *error = nil;
    } else {
        [LoggingService log:@"[测试] 测试失败！"];
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"测试失败: 返回值0x%llX != 期望值0x1234", result]}];
        }
    }
    
    return result;
}

- (uint64_t)testSimpleReturn:(uint64_t)testValue error:(NSError **)error {
    [LoggingService log:@"[测试] 开始简单返回值测试: 0x%llX", testValue];
    
    if (g_task_port == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无效的task port"}];
        }
        return 0;
    }
    
    mach_vm_address_t test_addr = 0;
    size_t test_size = 0x1000;
    
    kern_return_t kr = mach_vm_allocate(g_task_port, &test_addr, test_size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法分配测试内存"}];
        }
        return 0;
    }
    
    [LoggingService log:@"[测试] 分配测试内存: 0x%llX", test_addr];
    
    uint32_t test_code[3];
    
    uint32_t imm16 = (uint32_t)(testValue & 0xFFFF);
    test_code[0] = 0xD2800000 | (imm16 << 5);
    
    if (testValue > 0xFFFF) {
        uint32_t imm16_hi = (uint32_t)((testValue >> 16) & 0xFFFF);
        test_code[1] = 0xF2A00000 | (imm16_hi << 5);
        
        if (testValue > 0xFFFFFFFF) {
            uint32_t imm16_hi2 = (uint32_t)((testValue >> 32) & 0xFFFF);
            test_code[2] = 0xF2C00000 | (imm16_hi2 << 5);
        } else {
            test_code[2] = 0xD65F03C0;  // RET
        }
    } else {
        test_code[1] = 0xD65F03C0;  // RET
        test_code[2] = 0xD65F03C0;  // RET
    }
    
    kr = mach_vm_write(g_task_port, test_addr, (vm_offset_t)test_code, sizeof(test_code));
    if (kr != KERN_SUCCESS) {
        mach_vm_deallocate(g_task_port, test_addr, test_size);
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法写入测试代码"}];
        }
        return 0;
    }
    
    kr = mach_vm_protect(g_task_port, test_addr, test_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        mach_vm_deallocate(g_task_port, test_addr, test_size);
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:kr userInfo:@{NSLocalizedDescriptionKey: @"无法设置内存保护"}];
        }
        return 0;
    }
    
    [LoggingService log:@"[测试] 测试代码已写入"];
    
    uint64_t result = [self callFunctionAtAddress:test_addr parameters:@[] paramCount:0 error:error];
    
    [LoggingService log:@"[测试] 调用结果: 0x%llX (期望: 0x%llX)", result, testValue];
    
    mach_vm_deallocate(g_task_port, test_addr, test_size);
    
    if (result == testValue) {
        [LoggingService log:@"[测试]  测试成功！"];
        if (error) *error = nil;
    } else {
        [LoggingService log:@"[测试]  测试失败！"];
        if (error) {
            *error = [NSError errorWithDomain:@"RemoteCall" code:-2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"测试失败: 返回值0x%llX != 期望值0x%llX", result, testValue]}];
        }
    }
    
    return result;
}

@end
