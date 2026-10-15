#import "MemoryRegion.h"

@implementation MemoryRegion

- (instancetype)initWithStart:(mach_vm_address_t)start end:(mach_vm_address_t)end {
    self = [super init];
    if (self) {
        _start = start;
        _end = end;
    }
    return self;
}

- (mach_vm_size_t)size {
    if (!self.isValid) return 0;
    return (mach_vm_size_t)(_end - _start);
}

- (BOOL)containsAddress:(mach_vm_address_t)address {
    return address >= _start && address < _end;
}

- (BOOL)isValid {
    return _start > 0 && _end > _start;
}

+ (nullable instancetype)regionWithStart:(mach_vm_address_t)start
                                     end:(mach_vm_address_t)end
                                    info:(vm_region_submap_info_data_64_t)info {
    if (!(info.protection & VM_PROT_READ) || !(info.protection & VM_PROT_WRITE)) {
        return nil;
    }
    if (start >= end || start == 0) {
        return nil;
    }
    return [[self alloc] initWithStart:start end:end];
}

@end
