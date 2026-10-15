#import <UIKit/UIKit.h>

@interface SSCustomMenuView : UIView

@property (nonatomic, copy) void (^onOptionSelected)(NSInteger index);

- (instancetype)initWithOptions:(NSArray<NSString *> *)options;
- (void)showFromPoint:(CGPoint)point inView:(UIView *)view;
- (void)dismiss;

@end 