#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AccessRecord;
@class AccessHit;

/// 一条访问命中的「现场检查器」：
///   摘要 + 概览 / 反汇编 / 调用栈 / 寄存器 四个 Tab。
///   反汇编里的 b/bl 目标可点进去，顶部「返回」逐级回退。
@interface AccessHitInspectorViewController : UIViewController

- (instancetype)initWithRecord:(AccessRecord *)record hit:(AccessHit *)hit;

@end

NS_ASSUME_NONNULL_END
