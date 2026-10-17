#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@class AccessViewModel;

NS_ASSUME_NONNULL_BEGIN

@interface AccessPage : UIViewController <WKNavigationDelegate, UITextFieldDelegate>

@property (nonatomic, strong, readonly) AccessViewModel *viewModel;

@end

NS_ASSUME_NONNULL_END
