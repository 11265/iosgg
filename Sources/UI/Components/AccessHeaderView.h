#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AccessHeaderView;

@protocol AccessHeaderViewDelegate <NSObject>
- (void)accessHeaderDidTapAdd:(AccessHeaderView *)header;
- (void)accessHeaderDidTapMore:(AccessHeaderView *)header;
@end

/// 访问页顶部：状态点 + 运行状态 + 槽位 + 添加/更多
@interface AccessHeaderView : UIView

@property (nonatomic, weak, nullable) id<AccessHeaderViewDelegate> delegate;

- (void)updateWithRunning:(BOOL)running
                slotCount:(NSInteger)slotCount
                slotLimit:(NSInteger)slotLimit;

@end

NS_ASSUME_NONNULL_END
