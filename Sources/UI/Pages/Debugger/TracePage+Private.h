#import "UI/Pages/Debugger/TracePage.h"

// TracePage 内部属性 —— 供主实现文件和 Category 共享
@interface SSTrackPopViewController ()
@property (nonatomic, strong) UITextField *addressField;
@property (nonatomic, strong) UIButton *watchButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *startDebugButton;
@property (nonatomic, strong) UIButton *stopDebugButton;
@property (nonatomic, strong, readwrite) UITableView *tableView;
@property (nonatomic, strong, readwrite) NSMutableArray<SSTrackRecord *> *trackingData;
@property (nonatomic, strong, readwrite) NSMutableArray<NSNumber *> *watchAddresses;
@property (nonatomic, assign, readwrite) BOOL isDebugging;
@end
