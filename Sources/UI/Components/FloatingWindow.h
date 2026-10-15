#import <UIKit/UIKit.h>
#import "UI/Components/DraggableView.h"

@class MemoryPages;
@class SearchPage;
@class RecordPage;
@class AccessPage;

NS_ASSUME_NONNULL_BEGIN

@interface FloatingWindow : NSObject <DragViewDelegate, UITabBarControllerDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) UITabBarController *tabBarController;
@property (nonatomic, strong, readonly) UIWindow *dragWindow;
@property (nonatomic, strong) UIViewController *dragWindowController;
@property (nonatomic, strong, readonly) MemoryPages *memoryViewController;
@property (nonatomic, readonly) SearchPage *searchViewController;
@property (nonatomic, strong, readonly) RecordPage *recordViewController;
@property (nonatomic, readonly) AccessPage *accessViewController;

+ (instancetype)sharedInstance;
- (void)show;
- (void)hide;
- (void)showSearch;
- (void)showMemory;
- (void)showRecord;

@end

NS_ASSUME_NONNULL_END 