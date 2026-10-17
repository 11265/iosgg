//
//  SSModuleManager.m
//

#import "Core/Module/SSModuleManager.h"
#import "Services/LogService.h"

@interface SSModuleManager ()
@property (nonatomic, strong) NSMutableArray<id<SSModule>> *modules;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id<SSModule>> *moduleMap;
@property (nonatomic, assign) BOOL started;
@end

@implementation SSModuleManager

+ (instancetype)shared {
    static SSModuleManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _modules = [NSMutableArray array];
        _moduleMap = [NSMutableDictionary dictionary];
        _started = NO;
    }
    return self;
}

- (void)registerModule:(id<SSModule>)module {
    NSString *moduleId = [module moduleId];
    if (self.moduleMap[moduleId]) {
        [LoggingService log:[NSString stringWithFormat:@"[ModuleManager] 警告: 模块 %@ 已注册，跳过", moduleId]];
        return;
    }
    [self.modules addObject:module];
    self.moduleMap[moduleId] = module;
    [LoggingService log:[NSString stringWithFormat:@"[ModuleManager] 注册模块: %@ (%@)", moduleId, [module moduleDisplayName]]];
    [module moduleDidLoad];
    // 若已经调用过 startAllModules，立即补发 moduleDidStart
    if (self.started && [module respondsToSelector:@selector(moduleDidStart)]) {
        [module moduleDidStart];
    }
}

- (void)startAllModules {
    self.started = YES;
    for (id<SSModule> module in self.modules) {
        if ([module respondsToSelector:@selector(moduleDidStart)]) {
            [LoggingService log:[NSString stringWithFormat:@"[ModuleManager] 启动模块: %@", [module moduleId]]];
            [module moduleDidStart];
        }
    }
}

- (void)stopAllModules {
    self.started = NO;
    // 逆序停止
    for (id<SSModule> module in [self.modules reverseObjectEnumerator]) {
        if ([module respondsToSelector:@selector(moduleWillStop)]) {
            [LoggingService log:[NSString stringWithFormat:@"[ModuleManager] 停止模块: %@", [module moduleId]]];
            [module moduleWillStop];
        }
    }
}

- (nullable id<SSModule>)moduleWithId:(NSString *)moduleId {
    return self.moduleMap[moduleId];
}

- (NSArray<id<SSModule>> *)allModules {
    return [self.modules copy];
}

- (NSArray<NSDictionary *> *)allMoreMenuItems {
    NSMutableArray *items = [NSMutableArray array];
    for (id<SSModule> module in self.modules) {
        if ([module respondsToSelector:@selector(moreMenuItems)]) {
            NSArray *moduleItems = [module moreMenuItems];
            if (moduleItems.count > 0) {
                [items addObjectsFromArray:moduleItems];
            }
        }
    }
    return [items copy];
}

@end
