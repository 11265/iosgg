//
//  BreakpointHitPresenter.h
//  执行断点命中后的展示器：把命中的寄存器 + 调用栈立刻摆到用户面前
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSBreakpointHitPresenter : NSObject

+ (instancetype)sharedInstance;

/// 开始监听 kSSDebuggerDidHitBreakpointNotification（重复调用无副作用）
- (void)start;

@end

NS_ASSUME_NONNULL_END
