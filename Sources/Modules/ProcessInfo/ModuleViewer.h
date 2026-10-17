#import <Foundation/Foundation.h>
#import <mach/mach.h>

@interface ModuleInfo : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint64_t baseAddress;
@property (nonatomic, assign) uint64_t size;
@property (nonatomic, assign) uint64_t endAddress;
@property (nonatomic, copy) NSString *path;

@end

@interface ModuleViewer : NSObject

+ (instancetype)sharedInstance;

- (NSArray<ModuleInfo *> *)getAllModules;

- (ModuleInfo *)getModuleByName:(NSString *)moduleName;

- (ModuleInfo *)getModuleByAddress:(uint64_t)address;

- (uint64_t)getModuleBaseAddress:(NSString *)moduleName;

@end
