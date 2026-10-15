#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSMemoryHandler : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak) WKWebView *webView;

- (instancetype)initWithWebView:(WKWebView *)webView;
- (void)handleMemoryMessage:(WKScriptMessage *)message;

@end

NS_ASSUME_NONNULL_END 