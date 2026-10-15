#ifndef ProcessMemory_h
#define ProcessMemory_h

#import <stdint.h>
#import <mach/mach.h>
#import <sys/mman.h>

// 引入 TaskPortManager 头文件以使用 g_task_port 宏
#import "Services/TaskPortManager.h"

// 向后兼容：g_task_port 现由 TaskPortManager 单例管理
#define g_task_port ([TaskPortManager shared].taskPort)

#ifdef __cplusplus
extern "C" {
#endif
//读取内存
kern_return_t mach_vm_read_overwrite(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size,
                                     mach_vm_address_t data, mach_vm_size_t *outsize);
//写入内存
kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data,
                            mach_msg_type_number_t dataCnt);
//保护内存  
kern_return_t mach_vm_protect(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size,
                              boolean_t set_maximum, vm_prot_t new_protection);
//获取内存区域
kern_return_t mach_vm_region(vm_map_t target_task, mach_vm_address_t *address, mach_vm_size_t *size,
                             vm_region_flavor_t flavor, vm_region_info_t info,
                             mach_msg_type_number_t *infoCnt, mach_port_t *object_name);
//分配内存
kern_return_t mach_vm_allocate(vm_map_t target_task, mach_vm_address_t *address, mach_vm_size_t size, int flags);
//释放内存
kern_return_t mach_vm_deallocate(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size);


#ifdef __cplusplus
}
#endif

#endif /* ProcessMemory_h */
