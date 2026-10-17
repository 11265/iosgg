//
//  SSDebuggerModule.m
//

#import "Modules/Debugger/SSDebuggerModule.h"
#import "Services/LogService.h"

@implementation SSDebuggerModule

+ (instancetype)shared {
    static SSDebuggerModule *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)moduleId { return @"debugger"; }
- (NSString *)moduleDisplayName { return @"调试器"; }

- (void)moduleDidLoad {
    [LoggingService log:@"[SSDebuggerModule] 模块已加载"];
}

@end
