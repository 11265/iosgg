#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Filter settings model for pointer chain filtering.
@interface PointerFilterSettings : NSObject
@property (nonatomic, copy) NSString *moduleKeyword;
@property (nonatomic, assign) BOOL minLevelEnabled;
@property (nonatomic, assign) NSInteger minLevel;
@property (nonatomic, assign) BOOL maxLevelEnabled;
@property (nonatomic, assign) NSInteger maxLevel;
@property (nonatomic, assign) BOOL maxOffsetEnabled;
@property (nonatomic, assign) uint64_t maxOffset;
@property (nonatomic, assign) BOOL onlyValid;
@property (nonatomic, assign) BOOL valueEqualsEnabled;
@property (nonatomic, assign) uint64_t valueEquals;
@end

/// Overlay view for configuring pointer chain filter settings.
@interface FilterSettingsOverlay : UIView

@property (nonatomic, strong, readonly) UITextField *moduleField;
@property (nonatomic, strong, readonly) UITextField *minLevelField;
@property (nonatomic, strong, readonly) UITextField *maxLevelField;
@property (nonatomic, strong, readonly) UITextField *maxOffsetField;
@property (nonatomic, strong, readonly) UITextField *valueEqualsField;
@property (nonatomic, strong, readonly) UISwitch *validSwitch;

@property (nonatomic, copy, nullable) void (^onApply)(PointerFilterSettings *settings);
@property (nonatomic, copy, nullable) void (^onClose)(void);

- (instancetype)initWithFrame:(CGRect)frame current:(nullable PointerFilterSettings *)current;

@end

NS_ASSUME_NONNULL_END
