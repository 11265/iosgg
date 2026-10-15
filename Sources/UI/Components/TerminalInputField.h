#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerminalInputField : UIView

@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UITextField *textField;

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *placeholder;
@property (nonatomic, copy, nullable) NSString *value;

+ (instancetype)inputFieldWithTitle:(NSString *)title placeholder:(NSString *)placeholder;

- (void)configureWithTitle:(NSString *)title placeholder:(NSString *)placeholder;

@end

NS_ASSUME_NONNULL_END
