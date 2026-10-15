//
//  BreakpointHitPresenter.m
//  执行断点命中后的展示器
//
//  设计要点：
//   1. 只在"命中会暂停线程"（stopExecution == YES）时弹窗。不停顿模式下命中频率可能很高，
//      弹窗会糊满屏幕；那种场景只发通知（后续可接日志/列表）。
//   2. 弹窗内容直接复用 AccessRegisterViewController —— 它本来就会渲染"寄存器 + 调用栈"，
//      而调用栈正是"谁调用了这个函数"的答案。
//   3. 断点会让出错线程停在 break state，所以必须给用户一个"继续"出口：
//      该出口在 AccessRegisterViewController 的导航栏里（showsResumeControls = YES），
//      页面被下滑关闭时也会自动继续，避免游戏被永久冻住。
//

#import "UI/Pages/BreakpointHitPresenter.h"
#import "Constants/NotificationNames.h"
#import "Services/Debugger/SSDebugger.h"
#import "Services/LogService.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Pages/AccessRegisterViewController.h"

/// 同一断点极短时间连续命中时的弹窗节流（秒）
static const NSTimeInterval kBreakpointPopupThrottle = 0.4;

@interface SSBreakpointHitPresenter ()

@property (nonatomic, assign) NSTimeInterval lastPresentTime;
@property (nonatomic, weak) AccessRegisterViewController *presentedRegisterVC;
@property (nonatomic, assign) BOOL started;

@end

@implementation SSBreakpointHitPresenter

+ (instancetype)sharedInstance {
    static SSBreakpointHitPresenter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSBreakpointHitPresenter alloc] init];
    });
    return instance;
}

- (void)start {
    if (self.started) {
        return;
    }
    self.started = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBreakpointHit:)
                                                 name:kSSDebuggerDidHitBreakpointNotification
                                               object:nil];
    [LoggingService log:@"[断点] 命中展示器已启动"];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notification

- (void)handleBreakpointHit:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    uint64_t address = [userInfo[@"address"] unsignedLongLongValue];
    
    // 不停顿模式：命中只记日志，不弹窗（否则高频函数会把界面刷爆）
    if (![userInfo[@"stopExecution"] boolValue]) {
        [LoggingService log:@"[断点] 命中 0x%llX（不停顿模式，不弹窗）", address];
        return;
    }
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastPresentTime < kBreakpointPopupThrottle) {
        [LoggingService log:@"[断点] 命中 0x%llX，距上次弹窗过近，跳过弹窗", address];
        return;
    }
    if (self.presentedRegisterVC != nil) {
        // 已经有一个寄存器页在前面，不叠加
        [LoggingService log:@"[断点] 命中 0x%llX，已有寄存器页展示中，跳过弹窗", address];
        return;
    }
    self.lastPresentTime = now;
    
    [self presentRegisterPageWithUserInfo:userInfo address:address];
}

#pragma mark - UI

- (void)presentRegisterPageWithUserInfo:(NSDictionary *)userInfo address:(uint64_t)address {
    NSDictionary *breakpoint = userInfo[@"breakpoint"];
    NSArray *callStack = userInfo[@"callStack"];
    
    AccessRegisterViewController *vc = [[AccessRegisterViewController alloc] init];
    vc.registers = userInfo[@"registers"];
    vc.callStack = callStack;
    vc.instructionAddr = address;
    vc.memoryAddress = 0;
    vc.showsResumeControls = YES;  // 断点把线程停住了，页面必须提供"继续"出口
    
    vc.accessInfo = [NSString stringWithFormat:
        @"执行断点命中\n"
        @"地址:   0x%llX\n"
        @"类型:   %@\n"
        @"命中:   %@ 次\n"
        @"线程:   %@\n"
        @"调用栈: %lu 层",
        address,
        [breakpoint[@"software"] boolValue] ? @"软件断点(BRK)" : @"硬件执行断点",
        breakpoint[@"hitCount"] ?: @0,
        userInfo[@"threadId"] ?: @0,
        (unsigned long)callStack.count];
    
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    
    FloatingWindow *floatingWindow = [FloatingWindow sharedInstance];
    [floatingWindow show];
    
    UIViewController *presenter = floatingWindow.tabBarController;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    if (!presenter) {
        presenter = floatingWindow.window.rootViewController;
    }
    if (!presenter) {
        [LoggingService log:@"[断点] 找不到可用的展示控制器，无法弹出寄存器页"];
        return;
    }
    
    self.presentedRegisterVC = vc;
    [presenter presentViewController:vc animated:YES completion:nil];
    
    [LoggingService log:@"[断点] 命中 0x%llX，已弹出寄存器/调用栈页面（%lu 帧，frame0=%@, frame1=%@）",
        address,
        (unsigned long)callStack.count,
        callStack.count > 0 ? callStack[0] : @"-",
        callStack.count > 1 ? callStack[1] : @"-"];
}

@end
