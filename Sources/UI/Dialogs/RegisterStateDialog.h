#import <UIKit/UIKit.h>

@interface SSRegisterPopupView : UIView

@property (nonatomic, assign) uint64_t instructionAddress;

+ (instancetype)sharedInstance;
- (void)showInView:(UIView *)parentView;

@end 