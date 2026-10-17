//
//  SSRemoteModule.m
//

#import "Modules/Remote/SSRemoteModule.h"
#import "Services/LogService.h"
#import "UI/Pages/System/RemoteCallPage.h"

@implementation SSRemoteModule

+ (instancetype)shared {
    static SSRemoteModule *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)moduleId { return @"remote"; }
- (NSString *)moduleDisplayName { return @"远程控制"; }

- (void)moduleDidLoad {
    [LoggingService log:@"[SSRemoteModule] 模块已加载"];
}

- (NSArray<NSDictionary *> *)moreMenuItems {
    return @[
        @{@"title": @"远程调用", @"vcClass": [RemoteCallPage class]},
    ];
}

@end
