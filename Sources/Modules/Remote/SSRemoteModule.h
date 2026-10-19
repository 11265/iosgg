//
//  SSRemoteModule.h
//  远程控制模块入口
//

#import <Foundation/Foundation.h>
#import "App/Module/SSModuleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSRemoteModule : NSObject <SSModule>
+ (instancetype)shared;
@end

NS_ASSUME_NONNULL_END
