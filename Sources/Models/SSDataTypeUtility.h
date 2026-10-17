#import <Foundation/Foundation.h>
#import "Modules/Scanner/Scanner.h"

NS_ASSUME_NONNULL_BEGIN

/// 数据类型统一工具 —— 搜索页与记录页共用的唯一一份
/// 类型↔字符串↔字节宽度↔格式化↔输入解析 逻辑。
/// 重构前这些逻辑散落在 SearchPage.m / SearchPage+Actions.m /
/// RecordPage.m / RecordPage+Actions.m 四处，各自实现且互不一致。
@interface SSDataTypeUtility : NSObject

/// 枚举 → 规范字符串（@"u8"/@"i16"/@"i32"/@"i64"/@"f32"/@"f64"）
+ (NSString *)stringForType:(SearchDataType)type;

/// 字符串 → 枚举（无法识别时返回 SearchDataTypeI32）
+ (SearchDataType)typeFromString:(NSString *)string;

/// 类型占用字节数（写/读内存必须按此宽度，写满 8 字节会踩坏相邻数据）
+ (size_t)widthForType:(SearchDataType)type;

/// 原始 8 字节值 → 十六进制显示串（按类型宽度截断）
+ (NSString *)hexStringForValue:(uint64_t)value type:(SearchDataType)type;

/// 原始 8 字节值 → 十进制显示串（按类型解释）
+ (NSString *)decimalStringForValue:(uint64_t)value type:(SearchDataType)type;

/// 用户输入（十进制或 0x 十六进制）→ 可写入的原始 8 字节值
+ (uint64_t)rawValueFromInput:(NSString *)input type:(SearchDataType)type;

@end

NS_ASSUME_NONNULL_END
