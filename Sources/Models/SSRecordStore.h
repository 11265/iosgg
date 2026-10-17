#import <Foundation/Foundation.h>
#import "Models/SSMemoryRecord.h"

NS_ASSUME_NONNULL_BEGIN

/// 记录变更通知 —— 记录页监听它刷新列表（取代原先 VC 间直接调用）
extern NSNotificationName const kSSRecordStoreDidChangeNotification;

/// 两页共享的内存记录单一数据源（本次会话内，不落盘）。
@interface SSRecordStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, strong, readonly) NSArray<SSMemoryRecord *> *records;
@property (nonatomic, assign, readonly) NSUInteger count;

/// 批量添加，内部按地址（指针链按表达式）去重；有新增才发通知
- (void)addRecords:(NSArray<SSMemoryRecord *> *)records;

/// 按下标批量删除
- (void)removeRecordsAtIndexes:(NSIndexSet *)indexes;

- (void)removeAll;

- (nullable SSMemoryRecord *)recordAtIndex:(NSUInteger)index;

/// 普通地址查找（用于记录页 → 搜索页回跳定位）
- (nullable SSMemoryRecord *)recordForAddress:(uint64_t)address;

@end

NS_ASSUME_NONNULL_END
