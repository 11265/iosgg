#import <Foundation/Foundation.h>

// ============================================================================
// 统一通知常量 —— 所有跨 Service/UI 层的通知名称集中在此
// 避免各层互相 import 对方头文件
// ============================================================================

// 搜索通知 (Service ↔ UI)
extern NSString * const kSearchResultNotification;
extern NSString * const kResetSearchNotification;
extern NSString * const kSearchStartNotification;
extern NSString * const kSearchProgressNotification;
extern NSString * const kSearchFinishNotification;

// 调试器通知 (Service ↔ UI)
extern NSString * const kSSDebuggerDidHitWatchpointNotification;
extern NSString * const kSSDebuggerDidAddWatchpointNotification;
extern NSString * const kSSDebuggerStateChangedNotification;
extern NSString * const kSSDebuggerDidHitBreakpointNotification;
