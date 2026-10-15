#import "Services/ModuleViewer.h"
#import "Services/LogService.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>

@implementation ModuleInfo

- (NSString *)description {
    return [NSString stringWithFormat:@"Module: %@, Base: 0x%llX, Size: 0x%llX, Path: %@", 
            self.name, self.baseAddress, self.size, self.path];
}

@end

@interface ModuleViewer ()

@property (nonatomic, strong) NSMutableArray<ModuleInfo *> *cachedModules;
@property (nonatomic, strong) dispatch_queue_t moduleQueue;

@end

@implementation ModuleViewer

+ (instancetype)sharedInstance {
    static ModuleViewer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ModuleViewer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedModules = [NSMutableArray array];
        _moduleQueue = dispatch_queue_create("com.iosgg.moduleviewer", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSArray<ModuleInfo *> *)getAllModules {
    dispatch_sync(self.moduleQueue, ^{
        [self refreshModules];
    });
    
    return [self.cachedModules copy];
}

- (void)refreshModules {
    [self.cachedModules removeAllObjects];
    
    uint32_t imageCount = _dyld_image_count();
    
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (!imageName) continue;
        
        NSString *name = [NSString stringWithUTF8String:imageName];
        uint64_t baseAddress = (uint64_t)_dyld_get_image_header(i);
        
        ModuleInfo *module = [[ModuleInfo alloc] init];
        module.name = [name lastPathComponent];
        module.path = name;
        module.baseAddress = baseAddress;
        
        uint64_t moduleSize = [self calculateModuleSize:baseAddress];
        module.size = moduleSize;
        module.endAddress = baseAddress + moduleSize;
        
        [self.cachedModules addObject:module];
    }
    
    [LoggingService log:@"[模块查看] 共找到 %lu 个模块", (unsigned long)self.cachedModules.count];
}

- (uint64_t)calculateModuleSize:(uint64_t)baseAddress {
    const struct mach_header_64 *header = (const struct mach_header_64 *)baseAddress;
    
    if (header->magic != MH_MAGIC_64 && header->magic != MH_CIGAM_64) {
        return 0;
    }
    
    uint64_t totalSize = 0;
    const struct load_command *loadCmd = (const struct load_command *)(baseAddress + sizeof(struct mach_header_64));
    
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (loadCmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segmentCmd = (const struct segment_command_64 *)loadCmd;
            
            if (strcmp(segmentCmd->segname, "__PAGEZERO") != 0) {
                uint64_t segmentEnd = segmentCmd->vmaddr + segmentCmd->vmsize;
                if (segmentEnd > totalSize) {
                    totalSize = segmentEnd;
                }
            }
        }
        
        loadCmd = (const struct load_command *)((const uint8_t *)loadCmd + loadCmd->cmdsize);
    }
    
    return totalSize - baseAddress;
}

- (ModuleInfo *)getModuleByName:(NSString *)moduleName {
    NSArray<ModuleInfo *> *modules = [self getAllModules];
    
    for (ModuleInfo *module in modules) {
        if ([module.name isEqualToString:moduleName] || 
            [module.path isEqualToString:moduleName] ||
            [module.path containsString:moduleName]) {
            return module;
        }
    }
    
    return nil;
}

- (ModuleInfo *)getModuleByAddress:(uint64_t)address {
    NSArray<ModuleInfo *> *modules = [self getAllModules];
    
    for (ModuleInfo *module in modules) {
        if (address >= module.baseAddress && address < module.endAddress) {
            return module;
        }
    }
    
    return nil;
}

- (uint64_t)getModuleBaseAddress:(NSString *)moduleName {
    ModuleInfo *module = [self getModuleByName:moduleName];
    if (module) {
        return module.baseAddress;
    }
    return 0;
}

@end
