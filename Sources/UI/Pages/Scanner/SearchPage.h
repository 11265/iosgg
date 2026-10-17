#import <UIKit/UIKit.h>
#import "UI/Components/FloatingWindow.h"
#import "Modules/Scanner/Scanner.h"
#import "UI/Dialogs/EditValueDialog.h"
#import "Models/SSMemoryRecord.h"

NS_ASSUME_NONNULL_BEGIN

@class SSTrackPopViewController;

@interface SearchPage : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UITableView *tableView;
/// 当前搜索结果集（统一模型，取代旧的 NSAttributedString 拼串）
@property (nonatomic, strong) NSMutableArray<SSMemoryRecord *> *dataSource;
@property (nonatomic, strong) SSTrackPopViewController *trackPopVC;

- (void)updateSearchResults:(NSArray<NSNumber *> *)addresses withType:(SearchDataType)type;
- (void)updateSearchResults:(NSArray<NSNumber *> *)addresses totalCount:(size_t)totalCount withType:(SearchDataType)type;
- (void)pauseUpdates;
- (void)resumeUpdates;

/// 记录页回跳：切换到搜索页后定位并高亮该地址所在行（若在结果集中）
- (void)focusAddress:(uint64_t)address;

@end

NS_ASSUME_NONNULL_END 