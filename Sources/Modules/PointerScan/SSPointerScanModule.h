//
//  SSPointerScanModule.h
//  指针扫描模块入口（PtrScan 源码 in-process）
//

#import <Foundation/Foundation.h>
#import "App/Module/SSModuleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSPointerScanModule : NSObject <SSModule>
+ (instancetype)shared;
@end

NS_ASSUME_NONNULL_END
