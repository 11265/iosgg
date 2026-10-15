#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// --- Convenience Macros (Dark Style ImGui Theme) ---
// Use these in UI code for zero-overhead color access.
// They delegate to AppTheme class methods.
#define IMGUI_BG_COLOR            [AppTheme backgroundColor]
#define IMGUI_CHILD_BG            [AppTheme childBackgroundColor]
#define IMGUI_BORDER_COLOR        [AppTheme borderColor]
#define IMGUI_TITLE_BG            [AppTheme titleBackgroundColor]
#define IMGUI_TITLE_BG_ACTIVE     [AppTheme titleBackgroundActiveColor]
#define IMGUI_TEXT                [AppTheme textColor]
#define IMGUI_TEXT_DISABLED       [AppTheme textDisabledColor]
#define IMGUI_BUTTON              [AppTheme buttonColor]
#define IMGUI_BUTTON_HOVER        [AppTheme buttonHoverColor]
#define IMGUI_BUTTON_ACTIVE       [AppTheme buttonActiveColor]
#define IMGUI_FRAME_BG            [AppTheme frameBackgroundColor]
#define IMGUI_CHECKMARK           [AppTheme checkmarkColor]

// --- Convenience Font Helper ---
// Must be declared AFTER the AppTheme interface below.

typedef NS_ENUM(NSInteger, AppThemeStyle) {
    AppThemeStyleDefault,
    AppThemeStyleLight,
    AppThemeStyleDark
};

@interface AppTheme : NSObject

+ (instancetype)sharedTheme;

#pragma mark - Colors

+ (UIColor *)backgroundColor;
+ (UIColor *)childBackgroundColor;
+ (UIColor *)borderColor;
+ (UIColor *)titleBackgroundColor;
+ (UIColor *)titleBackgroundActiveColor;

+ (UIColor *)textColor;
+ (UIColor *)textDisabledColor;
+ (UIColor *)textHighlightColor;

+ (UIColor *)buttonColor;
+ (UIColor *)buttonHoverColor;
+ (UIColor *)buttonActiveColor;

+ (UIColor *)frameBackgroundColor;
+ (UIColor *)checkmarkColor;

+ (UIColor *)valueColor;
+ (UIColor *)writeTypeColor;
+ (UIColor *)readTypeColor;
+ (UIColor *)errorColor;

#pragma mark - Fonts

+ (UIFont *)monospaceFont:(CGFloat)size;
+ (UIFont *)monospaceBoldFont:(CGFloat)size;
+ (UIFont *)regularFont:(CGFloat)size;
+ (UIFont *)boldFont:(CGFloat)size;

#pragma mark - Dimensions

+ (CGFloat)cornerRadius;
+ (CGFloat)borderWidth;
+ (CGFloat)defaultSpacing;
+ (CGFloat)compactSpacing;

@end

// --- Convenience Font Helper ---
static inline UIFont *ImGuiFont(CGFloat size, BOOL bold) {
    return bold ? [AppTheme boldFont:size] : [AppTheme regularFont:size];
}

NS_ASSUME_NONNULL_END
