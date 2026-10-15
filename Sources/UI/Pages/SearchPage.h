#import <UIKit/UIKit.h>
#import "UI/Components/FloatingWindow.h"
#import "Services/Scanner/Scanner.h"
#import "UI/Dialogs/EditValueDialog.h"

NS_ASSUME_NONNULL_BEGIN

@class SSTrackPopViewController;

@interface SearchPage : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) SSTrackPopViewController *trackPopVC;

- (void)updateSearchResults:(NSArray<NSNumber *> *)addresses withType:(SearchDataType)type;
- (void)pauseUpdates;
- (void)resumeUpdates;

@end

NS_ASSUME_NONNULL_END 