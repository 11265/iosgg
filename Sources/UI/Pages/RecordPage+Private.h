#import "UI/Pages/RecordPage.h"

@interface RecordPage () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) UIButton *selectButton;
@property (nonatomic, strong) NSMutableSet *selectedIndexes;
@property (nonatomic, strong) NSMutableDictionary *addressIndexMap;
@property (nonatomic, assign) BOOL isUpdating;

- (void)buildAddressIndexMap;
- (void)updateAllValues;
@end
