#import "UI/Pages/Record/RecordPage.h"
#import "UI/Pages/Record/RecordPage+Private.h"
#import "UI/Pages/Record/RecordPage+Actions.h"
#import "UI/Pages/Scanner/SearchPage.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Dialogs/AddRecordDialog.h"
#import "Modules/MemoryAnalysis/PointerChainParser.h"
#import "Services/LogService.h"
#import "Modules/ProcessInfo/ProcessMemory.h"
#import "Models/AccessViewModel.h"
#import "Models/SSRecordStore.h"
#import "Models/SSDataTypeUtility.h"
#import <mach/mach.h>
#import "UI/Components/ThemeConfig.h"

// --- RecordCell ---
@interface RecordCell : UITableViewCell
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *typeLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *chainIcon;
@end

@implementation RecordCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        self.containerView = [[UIView alloc] init];
        self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.containerView];
        
        self.chainIcon = [[UILabel alloc] init];
        self.chainIcon.text = @"🔗";
        self.chainIcon.font = [UIFont systemFontOfSize:12];
        self.chainIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.chainIcon.hidden = YES;
        [self.containerView addSubview:self.chainIcon];
        
        self.addressLabel = [[UILabel alloc] init];
        self.addressLabel.font = ImGuiFont(13, NO);
        self.addressLabel.textColor = IMGUI_TEXT;
        self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.addressLabel];
        
        self.typeLabel = [[UILabel alloc] init];
        self.typeLabel.font = ImGuiFont(12, NO);
        self.typeLabel.textColor = IMGUI_TEXT_DISABLED;
        self.typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.typeLabel];
        
        self.valueLabel = [[UILabel alloc] init];
        self.valueLabel.font = ImGuiFont(13, YES);
        self.valueLabel.textColor = [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:1.0f]; // Gold
        self.valueLabel.textAlignment = NSTextAlignmentRight;
        self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.valueLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            
            [self.chainIcon.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
            [self.chainIcon.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:5],
            [self.chainIcon.widthAnchor constraintEqualToConstant:16],
            
            [self.addressLabel.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
            [self.addressLabel.leadingAnchor constraintEqualToAnchor:self.chainIcon.trailingAnchor constant:5],
            
            [self.typeLabel.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
            [self.typeLabel.leadingAnchor constraintEqualToAnchor:self.addressLabel.trailingAnchor constant:10],
            [self.typeLabel.widthAnchor constraintEqualToConstant:40],
            
            [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
            [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-10],
            [self.valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.typeLabel.trailingAnchor constant:10]
        ]];
    }
    return self;
}

@end

// --- RecordPage ---
@implementation RecordPage

- (SSRecordStore *)store { return [SSRecordStore sharedStore]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.selectedIndexes = [NSMutableSet new];
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    UIView *controlPanel = [[UIView alloc] init];
    controlPanel.backgroundColor = IMGUI_CHILD_BG;
    controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controlPanel];
    
    NSArray *buttons = @[
        @{@"title": @"选择", @"action": @"selectButtonTapped:", @"id": @"select"},
        @{@"title": @"修改", @"action": @"modifySelectedButtonTapped"},
        @{@"title": @"全改", @"action": @"modifyAllButtonTapped"},
        @{@"title": @"访问", @"action": @"accessButtonTapped"},
        @{@"title": @"关闭", @"action": @"closeButtonTapped"},
        @{@"title": @"计算", @"action": @"calculateButtonTapped"},
        @{@"title": @"清除", @"action": @"clearButtonTapped"},
        @{@"title": @"添加", @"action": @"addButtonTapped"},
    ];
    
    NSMutableArray *btnViews = [NSMutableArray array];
    for (NSDictionary *cfg in buttons) {
        SEL action = NSSelectorFromString(cfg[@"action"]);
        UIButton *btn = [self createCyberButtonWithTitle:cfg[@"title"] action:action];
        if ([cfg[@"id"] isEqualToString:@"select"]) {
            self.selectButton = btn;
        }
        [controlPanel addSubview:btn];
        [btnViews addObject:btn];
    }
    
    self.countLabel = [[UILabel alloc] init];
    self.countLabel.textColor = IMGUI_TEXT_DISABLED;
    self.countLabel.font = ImGuiFont(12, NO);
    self.countLabel.textAlignment = NSTextAlignmentRight;
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.countLabel];
    
    self.tableView = [[UITableView alloc] init];
    self.tableView.backgroundColor = IMGUI_CHILD_BG;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.layer.borderColor = IMGUI_BORDER_COLOR.CGColor;
    self.tableView.layer.borderWidth = 1.0;
    [self.tableView registerClass:[RecordCell class] forCellReuseIdentifier:@"RecordCell"];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [controlPanel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:5],
        [controlPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:5],
        [controlPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-5],
        [controlPanel.heightAnchor constraintEqualToConstant:70],
        
        [self.countLabel.bottomAnchor constraintEqualToAnchor:controlPanel.bottomAnchor constant:-2],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:controlPanel.trailingAnchor constant:-5],
        
        [self.tableView.topAnchor constraintEqualToAnchor:controlPanel.bottomAnchor constant:5],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:5],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-5],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-5]
    ]];
    
    CGFloat btnHeight = 24;
    CGFloat spacing = 5;
    NSInteger columns = 4;
    
    for (int i = 0; i < btnViews.count; i++) {
        UIButton *btn = btnViews[i];
        int row = i / columns;
        int col = i % columns;
        
        [NSLayoutConstraint activateConstraints:@[
            [btn.topAnchor constraintEqualToAnchor:controlPanel.topAnchor constant:row * (btnHeight + spacing)],
            [btn.heightAnchor constraintEqualToConstant:btnHeight],
            [btn.widthAnchor constraintEqualToAnchor:controlPanel.widthAnchor multiplier:0.25 constant:-(spacing * 3 / 4.0)]
        ]];
        
        if (col == 0) {
            [btn.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor].active = YES;
        } else {
            [btn.leadingAnchor constraintEqualToAnchor:[btnViews[i-1] trailingAnchor] constant:spacing].active = YES;
        }
    }
    
    // 监听记录库变化：任何来源（搜索页保存 / 弹窗添加 / 清除）都会触发刷新
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleStoreChanged:)
                                               name:kSSRecordStoreDidChangeNotification
                                             object:nil];
    
    [self updateCountLabel];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleStoreChanged:(NSNotification *)note {
    [self.selectedIndexes removeAllObjects];
    [self updateCountLabel];
    [self.tableView reloadData];
}

- (void)updateCountLabel {
    self.countLabel.text = [NSString stringWithFormat:@"Count: %lu", (unsigned long)[self store].count];
}

- (UIButton *)createCyberButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    btn.titleLabel.font = ImGuiFont(13, NO);
    btn.backgroundColor = IMGUI_BUTTON;
    btn.layer.cornerRadius = 2;
    if (action) {
        [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startUpdateTimer];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopUpdateTimer];
}

- (void)startUpdateTimer {
    [self stopUpdateTimer];
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(updateAllValues)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)stopUpdateTimer {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

#pragma mark - 兼容旧调用方（字典 → 模型 → Store）

/// 将旧的弱类型字典转换为统一模型，写入 SSRecordStore。
/// 由 EditValueDialog / AddRecordDialog 调用。
- (void)addAddressesToRecord:(NSArray *)addresses {
    NSMutableArray<SSMemoryRecord *> *records = [NSMutableArray array];
    for (NSDictionary *info in addresses) {
        SSMemoryRecord *rec = [[SSMemoryRecord alloc] init];
        rec.type = [SSDataTypeUtility typeFromString:info[@"type"]];
        rec.isPointerChain = [info[@"isPointerChain"] boolValue];
        if (rec.isPointerChain) {
            rec.pointerChain = info[@"pointerChain"];
            rec.chainExpression = info[@"chainExpression"];
        } else {
            uint64_t addr = 0;
            [[NSScanner scannerWithString:info[@"address"]] scanHexLongLong:&addr];
            rec.address = addr;
        }
        [records addObject:rec];
    }
    [[self store] addRecords:records];
}

#pragma mark - 指针链解析（集中一处，供刷新/回跳/访问复用）

- (uint64_t)resolvedAddressForRecord:(SSMemoryRecord *)rec {
    if (!rec.isPointerChain) return rec.address;
    NSArray *chain = rec.pointerChain;
    uint64_t moduleBase = 0;
    if (chain.count > 0) {
        NSDictionary *firstStep = chain[0];
        if ([firstStep[@"type"] isEqualToString:@"module"]) {
            moduleBase = [PointerChainResolver getModuleBase:firstStep[@"module"]];
            if (moduleBase == 0) return 0;   // 模块未找到
        }
    }
    NSError *error = nil;
    uint64_t addr = [PointerChainResolver resolvePointerChain:chain moduleBase:moduleBase error:&error];
    return (error || addr == 0) ? 0 : addr;
}

#pragma mark - 每秒刷新值

- (void)updateAllValues {
    if (self.isUpdating) return;
    self.isUpdating = YES;
    
    NSArray<SSMemoryRecord *> *snapshot = [[self store].records copy];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *updates = [NSMutableArray array];
        
        for (NSUInteger i = 0; i < snapshot.count; i++) {
            SSMemoryRecord *rec = snapshot[i];
            uint64_t addressValue = [self resolvedAddressForRecord:rec];
            
            NSString *errText = nil;
            if (rec.isPointerChain) {
                if (addressValue == 0) errText = @"[解析失败]";
            }
            
            uint64_t rawValue = 0;
            if (!errText) {
                size_t width = [SSDataTypeUtility widthForType:rec.type];
                mach_vm_size_t outsize = 0;
                kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), addressValue, width, (mach_vm_address_t)&rawValue, &outsize);
                if (kr != KERN_SUCCESS || outsize != width) errText = @"[读取失败]";
            }
            
            if (errText) {
                [updates addObject:@{@"index": @(i), @"errorText": errText}];
            } else {
                [updates addObject:@{@"index": @(i), @"value": @(rawValue)}];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSDictionary *update in updates) {
                NSInteger row = [update[@"index"] integerValue];
                if (row >= (NSInteger)snapshot.count) continue;
                SSMemoryRecord *rec = snapshot[row];
                rec.address = [self resolvedAddressForRecord:rec];   // 指针链刷新当前地址
                
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
                RecordCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                
                NSString *errorText = update[@"errorText"];
                if (errorText) {
                    if (cell && ![cell.valueLabel.text isEqualToString:errorText]) {
                        cell.valueLabel.text = errorText;
                        cell.valueLabel.textColor = [UIColor colorWithRed:1.0f green:0.3f blue:0.3f alpha:1.0f];
                    }
                    continue;
                }
                
                uint64_t rawValue = [update[@"value"] unsignedLongLongValue];
                if (rawValue == rec.lastValue) continue;   // 没变不刷新
                rec.lastValue = rawValue;
                
                if (!cell) continue;
                NSString *newValue = [SSDataTypeUtility decimalStringForValue:rawValue type:rec.type];
                if (![cell.valueLabel.text isEqualToString:newValue]) {
                    cell.valueLabel.text = newValue;
                    // 变化高亮：闪绿后回金色
                    [UIView animateWithDuration:0.3 animations:^{
                        cell.valueLabel.textColor = [UIColor colorWithRed:0.3f green:1.0f blue:0.3f alpha:1.0f];
                    } completion:^(BOOL finished) {
                        [UIView animateWithDuration:0.5 animations:^{
                            cell.valueLabel.textColor = [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:1.0f];
                        }];
                    }];
                }
            }
            self.isUpdating = NO;
        });
    });
}

#pragma mark - 记录 → 搜索页 回跳定位

- (void)locateRecordInSearchPage:(SSMemoryRecord *)record {
    uint64_t addr = [self resolvedAddressForRecord:record];
    if (addr == 0) {
        [LoggingService log:@"回跳失败：地址解析为 0（指针链可能失效）"];
        return;
    }
    [[FloatingWindow sharedInstance] showSearch];
    [[FloatingWindow sharedInstance].searchViewController focusAddress:addr];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self store].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RecordCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RecordCell" forIndexPath:indexPath];
    
    SSMemoryRecord *rec = [[self store] recordAtIndex:indexPath.row];
    if (!rec) return cell;
    
    if (rec.isPointerChain) {
        cell.chainIcon.hidden = NO;
        NSString *chainExpression = rec.chainExpression ?: @"指针链";
        if (chainExpression.length > 30) {
            chainExpression = [NSString stringWithFormat:@"%@...", [chainExpression substringToIndex:27]];
        }
        cell.addressLabel.text = chainExpression;
        cell.addressLabel.textColor = IMGUI_BUTTON_ACTIVE;
        cell.addressLabel.font = ImGuiFont(11, NO);
    } else {
        cell.chainIcon.hidden = YES;
        cell.addressLabel.text = rec.addressString;
        cell.addressLabel.textColor = IMGUI_TEXT;
        cell.addressLabel.font = ImGuiFont(13, NO);
    }
    
    cell.typeLabel.text = rec.typeString;
    cell.valueLabel.text = rec.lastValue ? [rec decimalValueString] : @"--";
    cell.valueLabel.textColor = [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:1.0f];
    
    // 选中态
    if (self.isSelectionMode && [self.selectedIndexes containsObject:@(indexPath.row)]) {
        cell.containerView.backgroundColor = IMGUI_BUTTON_ACTIVE;
    } else {
        cell.containerView.backgroundColor = [UIColor clearColor];
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 34.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isSelectionMode) {
        NSNumber *row = @(indexPath.row);
        if ([self.selectedIndexes containsObject:row]) {
            [self.selectedIndexes removeObject:row];
        } else {
            [self.selectedIndexes addObject:row];
        }
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    } else {
        // 非选择模式：点击记录行 → 回跳搜索页并定位该地址
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        SSMemoryRecord *rec = [[self store] recordAtIndex:indexPath.row];
        if (rec) [self locateRecordInSearchPage:rec];
    }
}

@end
