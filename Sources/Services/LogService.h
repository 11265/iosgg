// 消息输出/日记.h

#import <Foundation/Foundation.h>

// 控制日记输出的开关
#ifndef ENABLE_DIARY_LOG
#define ENABLE_DIARY_LOG 1  // 1表示开启日记输出，0表示关闭
#endif

@interface LoggingService : NSObject

+ (void)log:(NSString *)format, ...;
+ (void)logMessage:(NSString *)message;

/// 最近若干条日志（环形缓冲，最多 300 条）。供 MCP 桥等外部读取。
+ (NSArray<NSString *> *)recentLogs:(NSUInteger)limit;

@end


