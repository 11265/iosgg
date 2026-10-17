//
//  SSMemoryAnalysisModule.h
//  内存分析模块入口（指针扫描、反汇编、指令浏览等）
//

#import <Foundation/Foundation.h>
#import "Core/Module/SSModuleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSMemoryAnalysisModule : NSObject <SSModule>
+ (instancetype)shared;
@end

NS_ASSUME_NONNULL_END
