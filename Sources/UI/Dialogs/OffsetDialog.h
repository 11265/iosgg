#import <UIKit/UIKit.h>

@interface SSOffsetPopViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic, strong) UILabel *modeLabel;

+ (instancetype)offsetPopViewController;

@end

// 添加通知常量
extern NSString * const kOffsetAppliedNotification; 