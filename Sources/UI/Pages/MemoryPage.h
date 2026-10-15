#import <UIKit/UIKit.h>

@class InstructionBrowser;

@interface MemoryPages : UIViewController

@property (nonatomic, strong) UITextField *inputTextField;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) uint64_t baseAddress;
@property (nonatomic, assign) NSInteger patternLength;
@property (nonatomic, strong) NSArray<UIView *> *normalModeButtons;  // 普通模式按钮数组
@property (nonatomic, strong) UIButton *saveButton;  // 添加保存按钮属性
@property (nonatomic, assign) BOOL isSelectionMode;  // 添加选择模式标志


// 公共方法
- (void)jumpToAddress:(uint64_t)address;
- (void)selectDataType:(NSInteger)typeIndex;

@end 