//
//  SSProcessInfoModule.h
//  进程信息模块入口（内存区域、模块列表、TaskPort 管理）
//

#import <Foundation/Foundation.h>
#import "Core/Module/SSModuleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSProcessInfoModule : NSObject <SSModule>
+ (instancetype)shared;
@end

NS_ASSUME_NONNULL_END
