//
//  SSScannerModule.h
//  内存值扫描模块入口
//

#import <Foundation/Foundation.h>
#import "App/Module/SSModuleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSScannerModule : NSObject <SSModule>
+ (instancetype)shared;
@end

NS_ASSUME_NONNULL_END
