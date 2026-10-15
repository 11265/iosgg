#import "UI/Components/ThemeConfig.h"

@implementation AppTheme

+ (instancetype)sharedTheme {
    static AppTheme *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - Colors

+ (UIColor *)backgroundColor {
    return [UIColor colorWithRed:0.06f green:0.06f blue:0.06f alpha:1.00f];
}

+ (UIColor *)childBackgroundColor {
    return [UIColor colorWithRed:0.00f green:0.00f blue:0.00f alpha:0.00f];
}

+ (UIColor *)borderColor {
    return [UIColor colorWithRed:0.43f green:0.43f blue:0.50f alpha:0.50f];
}

+ (UIColor *)titleBackgroundColor {
    return [UIColor colorWithRed:0.04f green:0.04f blue:0.04f alpha:1.00f];
}

+ (UIColor *)titleBackgroundActiveColor {
    return [UIColor colorWithRed:0.16f green:0.29f blue:0.48f alpha:1.00f];
}

+ (UIColor *)textColor {
    return [UIColor colorWithRed:1.00f green:1.00f blue:1.00f alpha:1.00f];
}

+ (UIColor *)textDisabledColor {
    return [UIColor colorWithRed:0.50f green:0.50f blue:0.50f alpha:1.00f];
}

+ (UIColor *)textHighlightColor {
    return [UIColor colorWithRed:0.26f green:0.59f blue:0.98f alpha:1.00f];
}

+ (UIColor *)buttonColor {
    return [UIColor colorWithRed:0.26f green:0.59f blue:0.98f alpha:0.40f];
}

+ (UIColor *)buttonHoverColor {
    return [UIColor colorWithRed:0.26f green:0.59f blue:0.98f alpha:1.00f];
}

+ (UIColor *)buttonActiveColor {
    return [UIColor colorWithRed:0.06f green:0.53f blue:0.98f alpha:1.00f];
}

+ (UIColor *)frameBackgroundColor {
    return [UIColor colorWithRed:0.16f green:0.29f blue:0.48f alpha:0.54f];
}

+ (UIColor *)checkmarkColor {
    return [UIColor colorWithRed:0.26f green:0.59f blue:0.98f alpha:1.00f];
}

+ (UIColor *)valueColor {
    return [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:1.0f];
}

+ (UIColor *)writeTypeColor {
    return [UIColor systemRedColor];
}

+ (UIColor *)readTypeColor {
    return [UIColor systemGreenColor];
}

+ (UIColor *)errorColor {
    return [UIColor colorWithRed:1.0f green:0.4f blue:0.4f alpha:1.0f];
}

#pragma mark - Fonts

+ (UIFont *)monospaceFont:(CGFloat)size {
    return [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIFont *)monospaceBoldFont:(CGFloat)size {
    return [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightSemibold];
}

+ (UIFont *)regularFont:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIFont *)boldFont:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

#pragma mark - Dimensions

+ (CGFloat)cornerRadius {
    return 2.0f;
}

+ (CGFloat)borderWidth {
    return 1.0f;
}

+ (CGFloat)defaultSpacing {
    return 8.0f;
}

+ (CGFloat)compactSpacing {
    return 5.0f;
}

@end
