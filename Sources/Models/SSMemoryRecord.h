#import <Foundation/Foundation.h>
#import "Modules/Scanner/Scanner.h"

NS_ASSUME_NONNULL_BEGIN

/// 两页共用的内存记录模型 —— 取代原先搜索页的 NSAttributedString 拼串
/// 与记录页的弱类型 NSDictionary（{address,type,...}）。
///
/// 搜索页用它承载一批搜索结果（address+type+lastValue，非持久）；
/// 记录页用它承载已保存记录（可能带指针链）。两页通过 SSRecordStore 共享。
@interface SSMemoryRecord : NSObject

/// 当前有效地址：普通记录即自身地址；指针链记录为每帧解析后的动态地址
@property (nonatomic, assign) uint64_t address;

/// 数据类型（统一枚举，不再用字符串）
@property (nonatomic, assign) SearchDataType type;

/// 上一次读到的原始 8 字节值，用于"没变就不刷新"与变化高亮
@property (nonatomic, assign) uint64_t lastValue;

/// 是否已送 watchpoint 到访问页
@property (nonatomic, assign) BOOL watched;

/// 用户命名（可选）
@property (nonatomic, copy, nullable) NSString *label;

#pragma mark - 指针链（仅记录页使用）

@property (nonatomic, assign) BOOL isPointerChain;
/// 链步骤数组（PointerChainResolver 的产物）
@property (nonatomic, strong, nullable) NSArray *pointerChain;
/// 人类可读的链表达式，如 "模块+0x10+0x20"
@property (nonatomic, copy, nullable) NSString *chainExpression;

#pragma mark - 显示派生（统一走 SSDataTypeUtility）

- (NSString *)typeString;
- (NSString *)addressString;        // 0x%X
- (NSString *)hexValueString;       // 基于 lastValue
- (NSString *)decimalValueString;   // 基于 lastValue

/// 指针链记录返回链表达式，普通记录返回地址串（记录页地址列使用）
- (NSString *)displayAddressText;

@end

NS_ASSUME_NONNULL_END
