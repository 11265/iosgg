#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Custom table view cell for the memory browser display.
@interface MemoryCell : UITableViewCell

@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIButton *expandButton;
@property (nonatomic, copy, nullable) void (^expandBlock)(void);

@end

NS_ASSUME_NONNULL_END
