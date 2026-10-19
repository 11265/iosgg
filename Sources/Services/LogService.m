// 日记.m

#import "Services/LogService.h"
#import <Foundation/Foundation.h>
#import <pthread.h>

// 环形日志缓冲：MCP 桥通过 log_tail 让 AI 直接看到 tweak 内部发生了什么
static NSMutableArray<NSString *> *sRecentLogs = nil;
static pthread_mutex_t sRecentLogsLock = PTHREAD_MUTEX_INITIALIZER;
static const NSUInteger kRecentLogCapacity = 300;

@implementation LoggingService

+ (void)log:(NSString *)format, ... {
#if ENABLE_DIARY_LOG
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    pthread_mutex_lock(&sRecentLogsLock);
    if (!sRecentLogs) {
        sRecentLogs = [NSMutableArray array];
    }
    [sRecentLogs addObject:message];
    while (sRecentLogs.count > kRecentLogCapacity) {
        [sRecentLogs removeObjectAtIndex:0];
    }
    pthread_mutex_unlock(&sRecentLogsLock);
    
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    NSLog(@"[igg] iggxx %@", base64);
#endif
}

+ (void)logMessage:(NSString *)message {
#if ENABLE_DIARY_LOG
    [self log:@"%@", message];
#endif
}

+ (NSArray<NSString *> *)recentLogs:(NSUInteger)limit {
    pthread_mutex_lock(&sRecentLogsLock);
    NSUInteger count = MIN(limit, sRecentLogs.count);
    NSArray<NSString *> *result = @[];
    if (count > 0) {
        result = [[sRecentLogs subarrayWithRange:NSMakeRange(sRecentLogs.count - count, count)] copy];
    }
    pthread_mutex_unlock(&sRecentLogsLock);
    return result;
}

@end

