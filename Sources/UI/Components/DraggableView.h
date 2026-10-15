#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DragViewDelegate <NSObject>
- (void)dragViewDidTap:(UIView *)dragView;
@end

@interface DragView : UIView
@property (nonatomic, weak) id<DragViewDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
