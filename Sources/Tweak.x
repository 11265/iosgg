#import "UI/Components/FloatingWindow.h"
#import "UI/Components/DraggableView.h"
#import "Services/LogService.h"
#import "Core/Module/SSModuleManager.h"
#import "Modules/ProcessInfo/SSProcessInfoModule.h"
#import "Modules/Scanner/SSScannerModule.h"
#import "Modules/MemoryAnalysis/SSMemoryAnalysisModule.h"
#import "Modules/Debugger/SSDebuggerModule.h"
#import "Modules/Remote/SSRemoteModule.h"
#import "UI/Pages/System/BreakpointHitPresenter.h"

%hook UIApplication

-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    [LoggingService log:@"didFinishLaunchingWithOptions被调用"];
    [[FloatingWindow sharedInstance] show];
    return result;
}

-(void)applicationDidBecomeActive:(id)application {
    %orig;
    [LoggingService log:@"applicationDidBecomeActive被调用"];
    [[FloatingWindow sharedInstance] show];
}

%end

%hook UIWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    FloatingWindow *floatingWindow = [FloatingWindow sharedInstance];
    
    if (self == floatingWindow.dragWindow) {
        // dragWindow 只处理悬浮按钮的点击
        UIView *hitView = %orig;
        if ([hitView isKindOfClass:[DragView class]] || [hitView.superview isKindOfClass:[DragView class]]) {
            return hitView;
        }
        return nil;  // 不是悬浮按钮的点击就穿透
    } 
    else if (self == floatingWindow.window) {
        // 主窗口只在内容显示时处理点击
        if (!floatingWindow.contentContainer.hidden) {
            UIView *hitView = %orig;
            if (hitView) {
                return hitView;
            }
        }
        return nil;  // 让事件穿透到应用程序窗口
    }
    
    // 其他窗口（包括应用程序主窗口）正常处理点击
    return %orig;
}

%end

%ctor {
    [LoggingService log:@"Tweak 开始加载..."];

    // 注册所有功能模块（基础层先注册）
    SSModuleManager *mgr = [SSModuleManager shared];
    [mgr registerModule:[SSProcessInfoModule shared]];
    [mgr registerModule:[SSScannerModule shared]];
    [mgr registerModule:[SSMemoryAnalysisModule shared]];
    [mgr registerModule:[SSDebuggerModule shared]];
    [mgr registerModule:[SSRemoteModule shared]];
    [mgr startAllModules];

    [[SSBreakpointHitPresenter sharedInstance] start];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [LoggingService log:@"延迟2秒后尝试创建窗口"];
        [[FloatingWindow sharedInstance] show];
    });
}
