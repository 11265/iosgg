//
//  SSMemoryAnalysisModule.m
//

#import "Modules/MemoryAnalysis/SSMemoryAnalysisModule.h"
#import "Services/LogService.h"
#import "UI/Pages/PointerScan/PointerScanPage.h"

@implementation SSMemoryAnalysisModule

+ (instancetype)shared {
    static SSMemoryAnalysisModule *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)moduleId { return @"memory_analysis"; }
- (NSString *)moduleDisplayName { return @"内存分析"; }

- (void)moduleDidLoad {
    [LoggingService log:@"[SSMemoryAnalysisModule] 模块已加载"];
}

- (NSArray<NSDictionary *> *)moreMenuItems {
    return @[
        @{@"title": @"指针扫描", @"vcClass": [PointerScanPage class]},
    ];
}

@end
