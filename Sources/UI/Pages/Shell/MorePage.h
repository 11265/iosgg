#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MorePage : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *dataSource;

@end

NS_ASSUME_NONNULL_END
