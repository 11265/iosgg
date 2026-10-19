//
//  SSProcessInfoModule.m
//

#import "Modules/ProcessInfo/SSProcessInfoModule.h"
#import "Core/Process/TaskPortManager.h"
#import "Services/LogService.h"
#import "UI/Pages/ProcessInfo/ModulePage.h"
#import "UI/Pages/ProcessInfo/OffsetCalcPage.h"

@implementation SSProcessInfoModule

+ (instancetype)shared {
    static SSProcessInfoModule *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)moduleId { return @"process_info"; }
- (NSString *)moduleDisplayName { return @"进程信息"; }

- (void)moduleDidLoad {
    [LoggingService log:@"[SSProcessInfoModule] 模块已加载"];
    // 预热 TaskPortManager，确保 task port 尽早就绪
    [TaskPortManager shared];
}

- (NSArray<NSDictionary *> *)moreMenuItems {
    return @[
        @{@"title": @"模块查看", @"vcClass": [ModulePage class]},
        @{@"title": @"偏移计算", @"vcClass": [OffsetCalcPage class]},
    ];
}

@end
