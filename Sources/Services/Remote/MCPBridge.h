//
//  MCPBridge.h
//  给外部（PC 上的 MCP 服务器 / AI）用的进程内调试桥：
//  一个极简的"一行一个 JSON 请求 → 一行一个 JSON 响应"的 TCP 服务。
//
//  为什么不做成 HTTP/MCP 本体：
//    - MCP 协议细节（JSON-RPC、能力协商、SSE）放在 PC 侧实现，改起来不影响设备；
//    - 设备侧只需要稳定的 socket + JSON 编解码，出错面小。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSMCPBridge : NSObject

/// 监听端口（未启动为 0）
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) BOOL running;

+ (instancetype)sharedInstance;

/// 启动服务；port 传 0 用默认端口（27801）。返回是否成功。
- (BOOL)startOnPort:(uint16_t)port;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
