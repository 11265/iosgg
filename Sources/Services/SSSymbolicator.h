#import <Foundation/Foundation.h>
#import "Services/SSSymbol.h"

NS_ASSUME_NONNULL_BEGIN

/// ObjC runtime 的 IMP 反查表构建完成（用于被 strip 的 ObjC 包补方法名）。
/// 页面收到后应重新取一遍符号并刷新。
extern NSNotificationName const SSSymbolicatorObjCMethodsDidBecomeReadyNotification;

/// 外部符号映射更新（导入 / 手动命名 / 清空）。
extern NSNotificationName const SSSymbolicatorDidUpdateSymbolsNotification;

/// 进程内符号化服务（dyld 镜像 + LC_SYMTAB + LC_FUNCTION_STARTS）。
///
/// 用法：
///   SSSymbol *sym = [[SSSymbolicator shared] symbolForAddress:pc];
///   NSString *text = [sym shortText];      // "-[Foo bar]+0x24"
///
/// 说明：
///   - 只用于 UI 侧；不要在异常线程里调用（首次解析某个镜像会有毫秒级开销）。
///   - 结果按地址缓存；镜像表常驻，符号表按镜像懒加载。
@interface SSSymbolicator : NSObject

+ (instancetype)shared;

/// 普通地址（PC、函数入口、数据地址）。
- (nullable SSSymbol *)symbolForAddress:(uint64_t)address;

/// 调用栈里的返回地址（frame 1+）：内部按 address-1 查调用点。
- (nullable SSSymbol *)symbolForReturnAddress:(uint64_t)address;

/// 预加载（可放到后台队列调用），避免首次进页面时卡一下。
- (void)preloadForAddresses:(NSArray<NSNumber *> *)addresses;

/// 清空地址缓存（镜像表保留）。
- (void)invalidateCache;

/// 导入符号映射，覆盖 sub_xxx。
///
/// 支持：
///   - Il2CppDumper 的 script.json（取 ScriptMethod[].Address / Name）
///   - 文本：
///       UnityFramework+0x1A2B3C Player_Update
///       0x1A2B3C Player_Update
///       00000000001a2b3c T _Player_Update     （nm 风格）
/// module 为空时优先 UnityFramework，否则主可执行文件。
- (NSUInteger)importSymbolMapAtPath:(NSString *)path
                             module:(nullable NSString *)moduleName
                              error:(NSError **)error;
- (NSUInteger)importSymbolMapText:(NSString *)text module:(nullable NSString *)moduleName;

/// 手动命名某个地址所在的函数（按 模块+函数内偏移 持久化）。
- (BOOL)setSymbolName:(NSString *)name forAddress:(uint64_t)address;

/// 清空所有外部映射（不影响 nlist / ObjC / 函数边界）。
- (void)clearImportedSymbols;

@end

NS_ASSUME_NONNULL_END
