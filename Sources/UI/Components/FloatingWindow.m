#import "UI/Components/FloatingWindow.h"
#import "UI/Components/DraggableView.h"
#import "Services/LogService.h"

// 前向声明替代直接 import —— 解耦 FloatingWindow 与各页面
@class SearchPage;
@class RecordPage;
@class MemoryPages;
@class AccessPage;
@class MorePage;

@interface FloatingWindow () <DragViewDelegate>
@property (nonatomic, strong) UIViewController *rootVC;
@property (nonatomic, strong, readwrite) UIWindow *dragWindow;
@end

@implementation FloatingWindow

+ (instancetype)sharedInstance {
    static FloatingWindow *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)show {
    [LoggingService log:@"开始创建悬浮窗..."];
    if (!self.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setupWindow];
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.window.hidden = NO;
        self.dragWindow.hidden = NO;
        
        self.window.alpha = 0;
        self.window.transform = CGAffineTransformMakeScale(0.9, 0.9);
        
        [UIView animateWithDuration:0.4 
                              delay:0 
             usingSpringWithDamping:0.8 
              initialSpringVelocity:0.5 
                            options:UIViewAnimationOptionCurveEaseOut 
                         animations:^{
            self.window.alpha = 1;
            self.window.transform = CGAffineTransformIdentity;
        } completion:nil];
        
        self.contentContainer.userInteractionEnabled = YES;
    });
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 
                              delay:0 
                            options:UIViewAnimationOptionCurveEaseIn 
                         animations:^{
            self.contentContainer.transform = CGAffineTransformMakeScale(0.95, 0.95);
            self.contentContainer.alpha = 0;
        } completion:^(BOOL finished) {
            self.contentContainer.hidden = YES;
            self.contentContainer.transform = CGAffineTransformIdentity;
            self.contentContainer.alpha = 1;
            self.contentContainer.userInteractionEnabled = NO;
            // 不隐藏dragWindow，保持悬浮按钮可见
        }];
    });
}

- (void)setupWindow {
    [LoggingService log:@"在主线程创建悬浮窗"];
    
    // 监听设备旋转通知
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                           selector:@selector(handleOrientationChange) 
                                               name:UIDeviceOrientationDidChangeNotification 
                                             object:nil];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    // 创建主窗口
    self.window = [[UIWindow alloc] initWithFrame:screenBounds];
    self.window.windowLevel = UIWindowLevelStatusBar + 100;
    self.window.userInteractionEnabled = YES;
    self.window.backgroundColor = [UIColor clearColor];
    
    // 创建根视图控制器
    self.rootVC = [[UIViewController alloc] init];
    self.rootVC.view.backgroundColor = [UIColor clearColor];
    self.window.rootViewController = self.rootVC;
    
    // 创建内容容器
    self.contentContainer = [[UIView alloc] initWithFrame:screenBounds];
    self.contentContainer.backgroundColor = [UIColor blackColor];
    self.contentContainer.clipsToBounds = YES;
    self.contentContainer.hidden = YES;
    self.contentContainer.userInteractionEnabled = NO;
    [self.rootVC.view addSubview:self.contentContainer];
    
    // 修改内容容器约束
    self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentContainer.topAnchor constraintEqualToAnchor:self.rootVC.view.topAnchor],
        [self.contentContainer.leadingAnchor constraintEqualToAnchor:self.rootVC.view.leadingAnchor],
        [self.contentContainer.trailingAnchor constraintEqualToAnchor:self.rootVC.view.trailingAnchor],
        [self.contentContainer.bottomAnchor constraintEqualToAnchor:self.rootVC.view.bottomAnchor]
    ]];
    
    [self setupTabBarController];
    
    // 创建独立的dragWindow
    self.dragWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    self.dragWindow.windowLevel = UIWindowLevelStatusBar + 99;
    self.dragWindow.backgroundColor = [UIColor clearColor];
    
    // 创建独立的dragWindowController
    self.dragWindowController = [[UIViewController alloc] init];
    self.dragWindowController.view.backgroundColor = [UIColor clearColor];
    self.dragWindow.rootViewController = self.dragWindowController;
    self.dragWindow.userInteractionEnabled = YES;
    
    [self setupDragViewInView:self.dragWindowController.view];
    
    // 确保两个窗口都显示
    [self.window makeKeyAndVisible];
    self.dragWindow.hidden = NO;
    [self.dragWindow makeKeyWindow];  // 让dragWindow成为key window以确保接收触摸事件
    
    [LoggingService log:@"悬浮窗创建完成"];
}

- (void)handleOrientationChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        self.window.frame = screenBounds;
        self.dragWindow.frame = screenBounds;
        
        // 确保拖拽按钮位置适配
        UIView *dragView = [self findDragView];
        if (dragView) {
            [self adjustDragViewPosition:dragView];
        }
    });
}

- (void)setupTabBarController {
    self.tabBarController = [[UITabBarController alloc] init];
    self.tabBarController.delegate = self;
    
    UIViewController *searchVC = [(UIViewController *)[NSClassFromString(@"SearchPage") alloc] init];
    searchVC.title = @"搜索";
    if (@available(iOS 13.0, *)) {
        searchVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"搜索"
                                                          image:[UIImage systemImageNamed:@"magnifyingglass"]
                                                  selectedImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    }
    
    UIViewController *recordVC = [(UIViewController *)[NSClassFromString(@"RecordPage") alloc] init];
    recordVC.title = @"记录";
    if (@available(iOS 13.0, *)) {
        recordVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"记录"
                                                          image:[UIImage systemImageNamed:@"doc.text.fill"]
                                                  selectedImage:[UIImage systemImageNamed:@"doc.text.fill"]];
    }
    
    UIViewController *memoryVC = [(UIViewController *)[NSClassFromString(@"MemoryPages") alloc] init];
    memoryVC.title = @"内存";
    _memoryViewController = (MemoryPages *)memoryVC;
    if (@available(iOS 13.0, *)) {
        memoryVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"内存"
                                                          image:[UIImage systemImageNamed:@"memorychip"]
                                                  selectedImage:[UIImage systemImageNamed:@"memorychip"]];
    }
    
    UIViewController *accessVC = [(UIViewController *)[NSClassFromString(@"AccessPage") alloc] init];
    accessVC.title = @"访问";
    if (@available(iOS 13.0, *)) {
        accessVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"访问"
                                                          image:[UIImage systemImageNamed:@"safari"]
                                                  selectedImage:[UIImage systemImageNamed:@"safari.fill"]];
    }
    
    UIViewController *moreVC = [(UIViewController *)[NSClassFromString(@"MorePage") alloc] init];
    moreVC.title = @"更多";
    if (@available(iOS 13.0, *)) {
        moreVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"更多"
                                                          image:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                  selectedImage:[UIImage systemImageNamed:@"ellipsis.circle.fill"]];
    }
    
    self.tabBarController.viewControllers = @[searchVC, recordVC, memoryVC, accessVC, moreVC];
    
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = [UIColor darkGrayColor];
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor lightGrayColor]};
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
        appearance.stackedLayoutAppearance.normal.iconColor = [UIColor lightGrayColor];
        appearance.stackedLayoutAppearance.selected.iconColor = [UIColor whiteColor];
        
        self.tabBarController.tabBar.standardAppearance = appearance;
        if (@available(iOS 15.0, *)) {
            self.tabBarController.tabBar.scrollEdgeAppearance = appearance;
        }
        self.tabBarController.tabBar.translucent = NO;
    }
    
    // 移除 frame 设置，完全使用 AutoLayout
    self.tabBarController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:self.tabBarController.view];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tabBarController.view.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.tabBarController.view.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.tabBarController.view.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.tabBarController.view.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor]
    ]];
    
    self.tabBarController.view.userInteractionEnabled = YES;
}

- (void)setupDragViewInView:(UIView *)parentView {
    DragView *dragView = [[DragView alloc] initWithFrame:CGRectMake(
        [UIScreen mainScreen].bounds.size.width - 60,
        130,
        50,
        50
    )];
    dragView.delegate = self;
    dragView.layer.cornerRadius = 25;
    dragView.layer.shadowColor = [UIColor blackColor].CGColor;
    dragView.layer.shadowOffset = CGSizeMake(0, 2);
    dragView.layer.shadowOpacity = 0.3;
    dragView.layer.shadowRadius = 4;
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = dragView.bounds;
    gradient.cornerRadius = 25;
    gradient.colors = @[
        (__bridge id)[UIColor colorWithRed:0.4 green:0.6 blue:1.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0].CGColor
    ];
    [dragView.layer insertSublayer:gradient atIndex:0];
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 30, 30)];
    if (@available(iOS 13.0, *)) {
        UIImage *toolImage = [UIImage systemImageNamed:@"compass.fill"];
        imageView.image = [toolImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        imageView.image = [[UIImage imageNamed:@"compass"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    imageView.tintColor = [UIColor whiteColor];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    
    [dragView addSubview:imageView];
    [parentView addSubview:dragView];
}

#pragma mark - DragViewDelegate

- (void)dragViewDidTap:(UIView *)dragView {
    if (self.contentContainer.hidden) {
        self.contentContainer.hidden = NO;
        self.contentContainer.alpha = 0;
        self.contentContainer.transform = CGAffineTransformMakeScale(0.95, 0.95);
        self.contentContainer.userInteractionEnabled = YES;
        
        [UIView animateWithDuration:0.3 
                         animations:^{
            self.contentContainer.alpha = 1;
            self.contentContainer.transform = CGAffineTransformIdentity;
        }];
    } else {
        [self hide];
    }
}

- (UIView *)findDragView {
    for (UIView *subview in self.dragWindow.rootViewController.view.subviews) {
        if ([subview isKindOfClass:[DragView class]]) {
            return subview;
        }
    }
    return nil;
}

- (void)adjustDragViewPosition:(UIView *)dragView {
    CGRect bounds = self.dragWindow.bounds;
    CGFloat halfWidth = dragView.bounds.size.width / 2;
    CGFloat halfHeight = dragView.bounds.size.height / 2;
    
    CGPoint center = dragView.center;
    center.x = MAX(halfWidth, MIN(bounds.size.width - halfWidth, center.x));
    center.y = MAX(halfHeight, MIN(bounds.size.height - halfHeight, center.y));
    dragView.center = center;
}

- (SearchPage *)searchViewController {
    return (SearchPage *)self.tabBarController.viewControllers[0];
}

- (RecordPage *)recordViewController {
    return (RecordPage *)self.tabBarController.viewControllers[1];
}

- (AccessPage *)accessViewController {
    return (AccessPage *)self.tabBarController.viewControllers[3];
}

#pragma mark - Navigation Methods

- (void)showSearch {
    self.contentContainer.hidden = NO;
    self.contentContainer.userInteractionEnabled = YES;
    self.tabBarController.selectedIndex = 0;
}

- (void)showMemory {
    self.contentContainer.hidden = NO;
    self.contentContainer.userInteractionEnabled = YES;
    self.tabBarController.selectedIndex = 2;
}

- (void)showRecord {
    self.contentContainer.hidden = NO;
    self.contentContainer.userInteractionEnabled = YES;
    self.tabBarController.selectedIndex = 1;
}

@end