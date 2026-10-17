//
//  SSDebuggerModule.h
//  调试器模块入口
//

#import <Foundation/Foundation.h>
#import "Core/Module/SSModuleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSDebuggerModule : NSObject <SSModule>
+ (instancetype)shared;
@end

NS_ASSUME_NONNULL_END
