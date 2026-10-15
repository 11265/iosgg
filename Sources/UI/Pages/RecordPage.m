#import "UI/Pages/RecordPage.h"
#import "UI/Pages/RecordPage+Private.h"
#import "UI/Pages/RecordPage+Actions.h"
#import "UI/Pages/SearchPage.h"
#import "UI/Dialogs/AddRecordDialog.h"
#import "Services/Memory/PointerChainParser.h"
#import "Services/LogService.h"
#import "Services/ProcessMemory.h"
#import "Models/AccessViewModel.h"
#import "UI/Pages/AccessPage.h"
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
        
        // Container
        self.containerView = [[UIView alloc] init];
        self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.containerView];
        
        // Chain Icon
        self.chainIcon = [[UILabel alloc] init];
        self.chainIcon.text = @"🔗";
        self.chainIcon.font = [UIFont systemFontOfSize:12];
        self.chainIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.chainIcon.hidden = YES;
        [self.containerView addSubview:self.chainIcon];
        
        // Address
        self.addressLabel = [[UILabel alloc] init];
        self.addressLabel.font = ImGuiFont(13, NO);
        self.addressLabel.textColor = IMGUI_TEXT;
        self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.addressLabel];
        
        // Type
        self.typeLabel = [[UILabel alloc] init];
        self.typeLabel.font = ImGuiFont(12, NO);
        self.typeLabel.textColor = IMGUI_TEXT_DISABLED;
        self.typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.typeLabel];
        
        // Value
        self.valueLabel = [[UILabel alloc] init];
        self.valueLabel.font = ImGuiFont(13, YES);
        self.valueLabel.textColor = [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:1.0f]; // Gold
        self.valueLabel.textAlignment = NSTextAlignmentRight;
        self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.valueLabel];
        
        // Layout
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

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    // Selection state is handled manually in cellForRow to support multi-select style
}

@end

// --- RecordPage ---
@implementation RecordPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.selectedIndexes = [NSMutableSet new];
    self.addressIndexMap = [NSMutableDictionary dictionary];
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    if (!self.savedAddresses) {
        self.savedAddresses = [NSMutableArray array];
        [LoggingService log:@"记录页面: 初始化地址数组"];
    }
    
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
        if (cfg[@"enabled"] && ![cfg[@"enabled"] boolValue]) {
            btn.enabled = NO;
            btn.alpha = 0.5;
        }
        if ([cfg[@"id"] isEqualToString:@"select"]) {
            self.selectButton = btn;
        }
        [controlPanel addSubview:btn];
        [btnViews addObject:btn];
    }
    
    self.countLabel = [[UILabel alloc] init];
    self.countLabel.text = [NSString stringWithFormat:@"Count: %lu", (unsigned long)self.savedAddresses.count];
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
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-5]
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
            [btn.heightAnchor constraintEqualToConstant:btnHeight]
        ]];
        
        if (columns == 4) {
            [NSLayoutConstraint activateConstraints:@[
                [btn.widthAnchor constraintEqualToAnchor:controlPanel.widthAnchor multiplier:0.25 constant:-(spacing * 3 / 4.0)]
            ]];
            
            if (col == 0) {
                [btn.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor].active = YES;
            } else {
                [btn.leadingAnchor constraintEqualToAnchor:[btnViews[i-1] trailingAnchor] constant:spacing].active = YES;
            }
        }
    }
    
    [self buildAddressIndexMap];
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
    //[LoggingService log:@"记录页面: 启动自动更新定时器"];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopUpdateTimer];
    //[LoggingService log:@"记录页面: 停止自动更新定时器"];
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

- (void)buildAddressIndexMap {
    self.addressIndexMap = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < self.savedAddresses.count; i++) {
        self.addressIndexMap[self.savedAddresses[i][@"address"]] = @(i);
    }
}

- (void)addAddressesToRecord:(NSArray *)addresses {
    if (!self.savedAddresses) {
        self.savedAddresses = [NSMutableArray array];
    }
    
    for (NSDictionary *newAddress in addresses) {
        BOOL isDuplicate = NO;
        NSString *newAddressStr = newAddress[@"address"];
        
        for (NSDictionary *existingAddress in self.savedAddresses) {
            if ([existingAddress[@"address"] isEqualToString:newAddressStr]) {
                isDuplicate = YES;
                break;
            }
        }
        
        if (!isDuplicate) {
            [self.savedAddresses addObject:newAddress];
        }
    }
    
    [self buildAddressIndexMap];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.countLabel.text = [NSString stringWithFormat:@"Count: %lu", (unsigned long)self.savedAddresses.count];
        [self.tableView reloadData];
    });
}

- (void)updateAllValues {
    if (self.isUpdating) return;
    self.isUpdating = YES;
    
    NSArray *snapshot = [self.savedAddresses copy];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *updates = [NSMutableArray array];
        
        for (NSInteger i = 0; i < snapshot.count; i++) {
            NSDictionary *addressInfo = snapshot[i];
            NSString *address = addressInfo[@"address"];
            NSString *type = addressInfo[@"type"];
            
            uint64_t addressValue = 0;
            
            if ([addressInfo[@"isPointerChain"] boolValue]) {
                NSArray *chain = addressInfo[@"pointerChain"];
                NSError *error = nil;
                
                uint64_t moduleBase = 0;
                if (chain.count > 0) {
                    NSDictionary *firstStep = chain[0];
                    if ([firstStep[@"type"] isEqualToString:@"module"]) {
                        NSString *moduleName = firstStep[@"module"];
                        moduleBase = [PointerChainResolver getModuleBase:moduleName];
                        
                        if (moduleBase == 0) {
                            [updates addObject:@{@"index": @(i), @"value": @"[模块未找到]", @"error": @(YES)}];
                            continue;
                        }
                    }
                }
                
                addressValue = [PointerChainResolver resolvePointerChain:chain 
                                                              moduleBase:moduleBase 
                                                                   error:&error];
                
                if (error || addressValue == 0) {
                    [updates addObject:@{@"index": @(i), @"value": @"[解析失败]", @"error": @(YES)}];
                    continue;
                }
            } else {
                NSScanner *scanner = [NSScanner scannerWithString:address];
                [scanner scanHexLongLong:&addressValue];
            }
            
            uint64_t rawValue = 0;
            mach_vm_size_t outsize = 0;
            kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), addressValue, sizeof(uint64_t), (mach_vm_address_t)&rawValue, &outsize);
            
            if (kr != KERN_SUCCESS) {
                [updates addObject:@{@"index": @(i), @"value": @"[读取失败]", @"error": @(YES)}];
                continue;
            }
            
            NSString *valueStr;
            if ([type isEqualToString:@"i32"]) {
                int32_t value = (int32_t)rawValue;
                valueStr = [NSString stringWithFormat:@"%d", value];
            } else if ([type isEqualToString:@"i64"]) {
                int64_t value = (int64_t)rawValue;
                valueStr = [NSString stringWithFormat:@"%lld", value];
            } else if ([type isEqualToString:@"f32"]) {
                union { uint32_t i; float f; } u;
                u.i = (uint32_t)rawValue;
                valueStr = [NSString stringWithFormat:@"%.6f", u.f];
            } else if ([type isEqualToString:@"f64"]) {
                union { uint64_t i; double d; } u;
                u.i = rawValue;
                valueStr = [NSString stringWithFormat:@"%.6f", u.d];
            } else {
                valueStr = @"[未知类型]";
            }
            
            [updates addObject:@{@"index": @(i), @"value": valueStr ?: @"--", @"error": @(NO)}];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSDictionary *update in updates) {
                NSInteger row = [update[@"index"] integerValue];
                if (row >= self.savedAddresses.count) continue;
                
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
                RecordCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                if (cell) {
                    NSString *newValue = update[@"value"];
                    if (![cell.valueLabel.text isEqualToString:newValue]) {
                        cell.valueLabel.text = newValue;
                        
                        BOOL isError = [update[@"error"] boolValue];
                        if (isError) {
                            cell.valueLabel.textColor = [UIColor colorWithRed:1.0f green:0.3f blue:0.3f alpha:1.0f];
                        } else {
                            [UIView animateWithDuration:0.3 animations:^{
                                cell.valueLabel.textColor = [UIColor colorWithRed:0.3f green:1.0f blue:0.3f alpha:1.0f];
                            } completion:^(BOOL finished) {
                                [UIView animateWithDuration:0.5 animations:^{
                                    cell.valueLabel.textColor = [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:1.0f];
                                }];
                            }];
                        }
                    }
                }
            }
            self.isUpdating = NO;
        });
    });
}

- (void)updateValue:(NSString *)value forAddress:(NSString *)address {
    NSNumber *index = self.addressIndexMap[address];
    if (!index) return;
    
    NSInteger row = [index integerValue];
    if (row >= self.savedAddresses.count) return;
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
    RecordCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    
    if (cell && ![cell.valueLabel.text isEqualToString:value]) {
        cell.valueLabel.text = value ?: @"--";
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.savedAddresses.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RecordCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RecordCell" forIndexPath:indexPath];
    
    NSDictionary *addressInfo = self.savedAddresses[indexPath.row];
    
    if ([addressInfo[@"isPointerChain"] boolValue]) {
        cell.chainIcon.hidden = NO;
        NSString *chainExpression = addressInfo[@"chainExpression"];
        if (chainExpression.length > 30) {
            chainExpression = [NSString stringWithFormat:@"%@...", [chainExpression substringToIndex:27]];
        }
        cell.addressLabel.text = chainExpression ?: @"指针链";
        cell.addressLabel.textColor = IMGUI_BUTTON_ACTIVE;
        cell.addressLabel.font = ImGuiFont(11, NO);
    } else {
        cell.chainIcon.hidden = YES;
        cell.addressLabel.text = addressInfo[@"address"];
        cell.addressLabel.textColor = IMGUI_TEXT;
        cell.addressLabel.font = ImGuiFont(13, NO);
    }
    
    cell.typeLabel.text = addressInfo[@"type"];
    
    // Initial value text (will be updated by timer)
    if ([cell.valueLabel.text isEqualToString:@""] || cell.valueLabel.text == nil) {
         cell.valueLabel.text = @"--";
    }
    
    // Selection state
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
    }
}

@end
