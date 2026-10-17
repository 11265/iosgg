#import <UIKit/UIKit.h>
#import "Modules/Scanner/Scanner.h"
#import "Models/SSMemoryRecord.h"

NS_ASSUME_NONNULL_BEGIN

@class SSBaseAddressPopViewController;

@interface RecordPage : UIViewController

@property (nonatomic, assign) BOOL isSelectionMode;

/// 兼容旧调用方（EditValueDialog / AddRecordDialog）：接受弱类型字典数组，
/// 内部转换为 SSMemoryRecord 后统一写入 SSRecordStore。
- (void)addAddressesToRecord:(NSArray *)addresses;

/// 记录页 → 搜索页回跳：切换 Tab 并在搜索结果中定位该记录地址
- (void)locateRecordInSearchPage:(SSMemoryRecord *)record;

@end
NS_ASSUME_NONNULL_END
