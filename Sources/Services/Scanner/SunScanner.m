#import "Services/Scanner/SunScanner.h"
#import "Services/LogService.h"
#import "Services/ProcessMemory.h"
#import <mach/mach.h>

@interface SunScanner ()

@property (nonatomic, strong) dispatch_queue_t scanQueue;

@end

@implementation SunScanner

+ (instancetype)sharedInstance {
    static SunScanner *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SunScanner alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _scanQueue = dispatch_queue_create("com.iosgg.sunscanner", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)scanSunObjectsWithManagerBase:(uint64_t)managerBase
                            completion:(void(^)(NSArray *sunObjects, NSError *error))completion {
    
    dispatch_async(self.scanQueue, ^{
        [LoggingService log:@"[阳光扫描] 开始扫描阳光对象，管理器基址: 0x%llX", managerBase];
        
        NSMutableArray *foundObjects = [NSMutableArray array];
        
        mach_port_t task = mach_task_self();
        
        [LoggingService log:@"[阳光扫描] 使用当前进程task port: 0x%X", task];
        
        vm_address_t address = 0;
        vm_size_t size = 0;
        natural_t depth = 0;
        
        int regionCount = 0;
        int scannedRegions = 0;
        int totalSize = 0;
        
        while (1) {
            vm_region_submap_info_data_64_t info;
            mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
            
            kern_return_t kr = vm_region_recurse_64(task, &address, &size, &depth,
                                                     (vm_region_info_t)&info, &count);
            
            if (kr != KERN_SUCCESS) {
                if (kr == KERN_INVALID_ADDRESS) {
                    [LoggingService log:@"[阳光扫描] 扫描完成，到达内存末尾"];
                } else {
                    [LoggingService log:@"[阳光扫描] vm_region_recurse_64失败，kr=%d", kr];
                }
                break;
            }
            
            regionCount++;
            
            if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
                if (size >= sizeof(uint64_t)) {
                    scannedRegions++;
                    totalSize += size;
                    
                    [self scanRegionForSunObjects:address
                                            size:size
                                      managerBase:managerBase
                                      foundObjects:foundObjects];
                }
            }
            
            address += size;
        }
        
        [LoggingService log:@"[阳光扫描] 扫描统计: 总区域=%d, 可读区域=%d, 总大小=%dMB", 
         regionCount, scannedRegions, totalSize / (1024 * 1024)];
        [LoggingService log:@"[阳光扫描] 扫描完成，找到 %lu 个可能的阳光对象", (unsigned long)foundObjects.count];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(foundObjects, nil);
            }
        });
    });
}

- (void)scanRegionForSunObjects:(mach_vm_address_t)regionStart
                           size:(mach_vm_size_t)regionSize
                     managerBase:(uint64_t)managerBase
                     foundObjects:(NSMutableArray *)foundObjects {
    
    mach_port_t task = mach_task_self();
    
    const size_t chunkSize = 4096;
    uint8_t buffer[chunkSize];
    
    int matchCount = 0;
    int validateCount = 0;
    
    for (mach_vm_address_t offset = 0; offset < regionSize; offset += chunkSize) {
        mach_vm_address_t readAddr = regionStart + offset;
        mach_vm_size_t readSize = chunkSize;
        
        if (offset + chunkSize > regionSize) {
            readSize = regionSize - offset;
        }
        
        mach_vm_size_t outSize = 0;
        kern_return_t kr = mach_vm_read_overwrite(task, readAddr, readSize,
                                                   (mach_vm_address_t)buffer, &outSize);
        
        if (kr != KERN_SUCCESS || outSize < sizeof(uint64_t)) {
            continue;
        }
        
        for (size_t i = 0; i <= outSize - sizeof(uint64_t); i += sizeof(uint64_t)) {
            uint64_t *ptr = (uint64_t *)(buffer + i);
            uint64_t value = *ptr;
            
            if (value == managerBase) {
                matchCount++;
                mach_vm_address_t possibleObjectAddr = readAddr + i - 0x08;
                
                int sunType = 0;
                if ([self validateSunObject:possibleObjectAddr managerBase:managerBase sunType:&sunType]) {
                    validateCount++;
                    NSDictionary *sunInfo = @{
                        @"address": @(possibleObjectAddr),
                        @"type": @(sunType),
                        @"managerBase": @(managerBase)
                    };
                    
                    [foundObjects addObject:sunInfo];
                    [LoggingService log:@"[阳光扫描] 找到阳光对象: 0x%llX, 类型: %d", possibleObjectAddr, sunType];
                }
            }
        }
    }
    
    if (matchCount > 0) {
        [LoggingService log:@"[阳光扫描] 区域 0x%llX: 匹配=%d, 验证通过=%d", 
         regionStart, matchCount, validateCount];
    }
}

- (BOOL)validateSunObject:(uint64_t)objectAddress
              managerBase:(uint64_t)managerBase
                   sunType:(int *)sunType {
    
    mach_port_t task = mach_task_self();
    
    uint64_t managerPtr = 0;
    mach_vm_size_t outSize = 0;
    kern_return_t kr = mach_vm_read_overwrite(task, objectAddress + 0x08, sizeof(uint64_t),
                                               (mach_vm_address_t)&managerPtr, &outSize);
    
    if (kr != KERN_SUCCESS || managerPtr != managerBase) {
        return NO;
    }
    
    uint32_t type = 0;
    kr = mach_vm_read_overwrite(task, objectAddress + 0x74, sizeof(uint32_t),
                                 (mach_vm_address_t)&type, &outSize);
    
    if (kr != KERN_SUCCESS) {
        return NO;
    }
    
    if (type == 4 || type == 5 || type == 6) {
        if (sunType) {
            *sunType = (int)type;
        }
        return YES;
    }
    
    return NO;
}

@end
