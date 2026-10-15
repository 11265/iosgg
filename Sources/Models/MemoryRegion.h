#import <Foundation/Foundation.h>
#import <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

/// 内存区域模型，封装 C 结构体 AddressRange
@interface MemoryRegion : NSObject

@property (nonatomic, assign) mach_vm_address_t start;
@property (nonatomic, assign) mach_vm_address_t end;

- (instancetype)initWithStart:(mach_vm_address_t)start end:(mach_vm_address_t)end;

/// 区域大小（字节）
- (mach_vm_size_t)size;

/// 判断地址是否在此区域内
- (BOOL)containsAddress:(mach_vm_address_t)address;

/// 判断是否为有效区域（start < end 且非零）
- (BOOL)isValid;

/// 从 vm_region_submap_info 创建，仅当区域为 可读+可写 时返回非 nil
+ (nullable instancetype)regionWithStart:(mach_vm_address_t)start
                                     end:(mach_vm_address_t)end
                                    info:(vm_region_submap_info_data_64_t)info;

@end

NS_ASSUME_NONNULL_END
