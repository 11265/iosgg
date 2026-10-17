#import <Foundation/Foundation.h>
#import "Modules/Scanner/Scanner.h"

NS_ASSUME_NONNULL_BEGIN

/// 搜索结果模型，封装 C 结构体 SearchResult
@interface ScanResult : NSObject

/// 匹配数量
@property (nonatomic, assign) size_t matchCount;

/// 结果文件路径（临时文件）
@property (nonatomic, copy, nullable) NSString *resultFilePath;

/// 搜索使用的数据类型
@property (nonatomic, assign) SearchDataType dataType;

/// 搜索结果地址数组（从文件读取）
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *addresses;

- (instancetype)initWithMatchCount:(size_t)count
                     resultFilePath:(nullable NSString *)path
                          dataType:(SearchDataType)type;

/// 从 C 结构体创建
+ (instancetype)resultWithCount:(size_t)count path:(nullable const char *)path type:(SearchDataType)type;

/// 从结果文件加载地址列表
- (NSArray<NSNumber *> *)loadAddresses;

/// 是否为空结果
- (BOOL)isEmpty;

@end

NS_ASSUME_NONNULL_END
