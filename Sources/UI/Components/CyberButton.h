#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CyberButtonStyle) {
    CyberButtonStyleDefault,
    CyberButtonStylePrimary,
    CyberButtonStyleDanger,
    CyberButtonStyleSuccess
};

@interface CyberButton : UIButton

@property (nonatomic, assign) CyberButtonStyle style;

+ (instancetype)buttonWithTitle:(NSString *)title;
+ (instancetype)buttonWithTitle:(NSString *)title style:(CyberButtonStyle)style;

- (void)configureWithTitle:(NSString *)title style:(CyberButtonStyle)style;
- (void)setLoading:(BOOL)loading;

@end

NS_ASSUME_NONNULL_END
