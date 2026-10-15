#import "UI/Pages/MemoryPage.h"

@class InstructionBrowser;
@class DisplayItem;

// MemoryPage 内部属性 —— 供主实现文件和 Category 共享
@interface MemoryPages () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) NSMutableArray<DisplayItem *> *displayItems;
@property (nonatomic, strong) UIView *dataTypeContainer;
@property (nonatomic, strong) NSMutableArray<UIButton *> *typeButtons;
@property (nonatomic, assign) NSInteger selectedTypeIndex;
@property (nonatomic, strong) InstructionBrowser *instructionBrowser;
@property (nonatomic, assign) NSInteger highlightedRow;
@property (nonatomic, strong) UIAlertController *editAlert;
@property (nonatomic, strong) NSArray *searchModeButtons;
@property (nonatomic, strong) NSArray *editModeButtons;
@property (nonatomic, strong) NSMutableSet *selectedIndexes;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) dispatch_queue_t updateQueue;
@property (nonatomic, strong) NSMutableDictionary *previousValues;
@property (nonatomic, strong) NSMutableDictionary *cellColors;
@property (nonatomic, strong) NSMutableDictionary *colorResetTimers;
@property (nonatomic, strong) UILabel *selectionCountLabel;
@property (nonatomic, strong) UIButton *toggleModeButton;
@property (nonatomic, strong) UIButton *exportAllButton;
@end
