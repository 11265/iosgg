#import "UI/Pages/Record/RecordPage.h"

@interface RecordPage () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) UIButton *selectButton;
@property (nonatomic, strong) NSMutableSet *selectedIndexes;
@property (nonatomic, assign) BOOL isUpdating;

- (void)updateAllValues;
- (uint64_t)resolvedAddressForRecord:(SSMemoryRecord *)rec;
@end
