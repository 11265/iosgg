//
//  SSPointerScanModule.m
//

#import "Modules/PointerScan/SSPointerScanModule.h"
#import "Services/LogService.h"
#import "UI/Pages/PointerScan/PointerScanPage.h"

@implementation SSPointerScanModule

+ (instancetype)shared {
    static SSPointerScanModule *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)moduleId { return @"pointer_scan"; }
- (NSString *)moduleDisplayName { return @"指针扫描"; }

- (void)moduleDidLoad {
    [LoggingService log:@"[SSPointerScanModule] 模块已加载"];
}

- (NSArray<NSDictionary *> *)moreMenuItems {
    return @[
        @{@"title": @"指针扫描", @"vcClass": [PointerScanPage class]},
    ];
}

@end
