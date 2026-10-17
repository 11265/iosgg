#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, SSSymbolKind) {
    SSSymbolKindUnknown = 0,
    SSSymbolKindFunction,
    SSSymbolKindObjC,
    SSSymbolKindSwift,
};

/// 一个地址的符号化结果。
///
/// 约定：
///   - `address` 已经做过 PAC 归一化；
///   - `imageOffset` 是相对 `__TEXT` 基址的偏移（与「计算偏移」功能一致，可直接拿去 IDA/Ghidra 对照）；
///   - `functionOffset` 是相对函数起点的偏移，没有函数边界时可能为 0。
@interface SSSymbol : NSObject

@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint64_t imageBase;
@property (nonatomic, assign) uint64_t imageOffset;
@property (nonatomic, copy, nullable) NSString *imageName;
@property (nonatomic, copy, nullable) NSString *rawName;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, assign) uint64_t functionStart;
@property (nonatomic, assign) uint64_t functionOffset;
@property (nonatomic, assign) SSSymbolKind kind;
@property (nonatomic, assign) BOOL hasRealName;

/// "func+0x24"；没有名字时返回 nil（例如只剩模块偏移）
- (nullable NSString *)formatted;

/// "pvzfree+0x1B2C4"
- (NSString *)moduleText;

/// formatted ?: moduleText ?: "0x..."
- (NSString *)shortText;

@end

NS_ASSUME_NONNULL_END
