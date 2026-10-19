//
//  SSModuleProtocol.h
//  所有功能模块必须遵守的协议。
//  新增模块只需实现此协议并在 Tweak.x 中调用 [SSModuleManager registerModule:] 即可接入。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SSModule <NSObject>

@required

/// 模块唯一标识符，如 @"scanner"、@"debugger"
- (NSString *)moduleId;

/// 模块显示名称，如 @"内存扫描"、@"调试器"
- (NSString *)moduleDisplayName;

/// 模块注册后立即调用，适合做一次性初始化（不依赖进程状态）
- (void)moduleDidLoad;

@optional

/// 所有模块加载完毕、进程就绪后调用（在 moduleDidLoad 之后）
- (void)moduleDidStart;

/// 模块停止前调用（Tweak 卸载或进程退出时）
- (void)moduleWillStop;

/// 向 MorePage 贡献菜单项。
/// 每项格式：@{@"title": @"显示文字", @"vcClass": [SomePage class]}
/// MorePage 会聚合所有模块的菜单项动态渲染。
- (NSArray<NSDictionary *> *)moreMenuItems;

@end

NS_ASSUME_NONNULL_END
