//
//  SSScannerModule.m
//

#import "Modules/Scanner/SSScannerModule.h"
#import "Modules/Scanner/ScannerState.h"
#import "Services/LogService.h"
#import "UI/Pages/Scanner/SunScanPage.h"

@implementation SSScannerModule

+ (instancetype)shared {
    static SSScannerModule *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)moduleId { return @"scanner"; }
- (NSString *)moduleDisplayName { return @"内存扫描"; }

- (void)moduleDidLoad {
    [LoggingService log:@"[SSScannerModule] 模块已加载"];
    // 触发 ScannerState 单例初始化
    [ScannerState shared];
}

- (NSArray<NSDictionary *> *)moreMenuItems {
    return @[
        @{
            @"title": @"对PVZ调用",
            @"vcClass": [SunScannerPage class],
            @"setupBlock": ^(UIViewController *vc) {
                ((SunScannerPage *)vc).sunManagerBase = 0;
            }
        },
    ];
}

@end
