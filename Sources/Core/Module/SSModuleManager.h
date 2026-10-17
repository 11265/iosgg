//
//  SSModuleManager.h
//  模块注册表 + 生命周期管理器（单例）。
//

#import <Foundation/Foundation.h>
#import "Core/Module/SSModuleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSModuleManager : NSObject

+ (instancetype)shared;

/// 注册模块，立即调用 moduleDidLoad
- (void)registerModule:(id<SSModule>)module;

/// 启动所有已注册模块（调用 moduleDidStart，需在全部 registerModule 之后调用一次）
- (void)startAllModules;

/// 停止所有模块（调用 moduleWillStop）
- (void)stopAllModules;

/// 按 moduleId 查找模块，未注册则返回 nil
- (nullable id<SSModule>)moduleWithId:(NSString *)moduleId;

/// 所有已注册模块（按注册顺序）
@property (nonatomic, readonly) NSArray<id<SSModule>> *allModules;

/// 聚合所有模块的 moreMenuItems，供 MorePage 动态渲染
@property (nonatomic, readonly) NSArray<NSDictionary *> *allMoreMenuItems;

@end

NS_ASSUME_NONNULL_END
