// 系统框架
#import "Core/Memory/SSMemoryBridge.h"

// 自定义视图控制器
#import "UI/Pages/Scanner/SearchPage.h"
#import "UI/Dialogs/EditValueDialog.h"
#import "UI/Dialogs/CompareDialog.h"
#import "UI/Dialogs/OffsetDialog.h"
#import "UI/Dialogs/SignatureDialog.h"
#import "UI/Pages/Debugger/TracePage.h"
#import "UI/Dialogs/FuzzySearchDialog.h"
#import "UI/Dialogs/RegisterStateDialog.h"
#import "UI/Dialogs/SearchDialog.h"
#import "UI/Pages/Record/RecordPage.h"

// 工具类
#import "Services/LogService.h"
#import "External/lz4/lz4.h"

#import "UI/Components/ThemeConfig.h"
#import "UI/Pages/Scanner/SearchPage+Actions.h"
#import "Models/SSDataTypeUtility.h"

// 在文件开头添加回调函数定义
static void searchResultCallback(uint64_t* results, size_t count, size_t totalCount, SearchDataType type) {
    [LoggingService log:@"搜索回调被触发 - 回传: %zu / 命中: %zu, 类型: %d", count, totalCount, type];
    
    SearchPage *searchVC = [FloatingWindow sharedInstance].searchViewController;
    if (!searchVC) {
        [LoggingService log:@"错误：无法获取搜索视图控制器实例"];
        return;
    }
    
    // 扫描器只回传前 2000 条地址，这里不需要再截断，也不会在百万级结果上装箱
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        [addresses addObject:@(results[i])];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [searchVC updateSearchResults:addresses totalCount:totalCount withType:type];
    });
}

@interface SearchPage () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) dispatch_queue_t updateQueue;
@property (nonatomic, strong) UISwitch *modeSwitch;
@property (nonatomic, strong) NSArray *searchModeButtons;
@property (nonatomic, strong) NSArray *editModeButtons;
@property (nonatomic, strong) NSMutableSet *selectedIndexes;
@end

@implementation SearchPage {
    UIColor *addressColor;    // 绿色
    UIColor *hexColor;        // 黄色
    UIColor *decimalColor;    // 蓝色
    UIColor *typeColor;       // 紫色
    UIColor *staticAddrColor; // 静态地址颜色 (绿色)
    UIColor *dynamicAddrColor; // 动态地址颜色 (橙色)
}

- (UIButton *)createCyberButtonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    btn.titleLabel.font = ImGuiFont(13, NO);
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 2; // Slight rounding like ImGui
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    // 在这里添加代理设置
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    // 注册单元格
    [self.tableView registerClass:[UITableViewCell class] 
           forCellReuseIdentifier:@"Cell"];
    
    // 创建工具栏容器
    UIStackView *toolbarStack = [[UIStackView alloc] init];
    toolbarStack.axis = UILayoutConstraintAxisHorizontal;
    toolbarStack.distribution = UIStackViewDistributionEqualSpacing;
    toolbarStack.alignment = UIStackViewAlignmentCenter;
    toolbarStack.spacing = 8; // Slightly tighter
    [self.view addSubview:toolbarStack];
    
    // 设置工具栏约束
    toolbarStack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [toolbarStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:5],
        [toolbarStack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:80], // Space for Clear button
        [toolbarStack.heightAnchor constraintEqualToConstant:35]
    ]];
    
    // 创建清除按钮
    UIButton *clearButton = [self createCyberButtonWithTitle:@"Clear" color:IMGUI_BUTTON action:@selector(clearTapped)];
    [self.view addSubview:clearButton];
    
    // 设置清除按钮约束
    [NSLayoutConstraint activateConstraints:@[
        [clearButton.centerYAnchor constraintEqualToAnchor:toolbarStack.centerYAnchor],
        [clearButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10],
        [clearButton.widthAnchor constraintEqualToConstant:60],
        [clearButton.heightAnchor constraintEqualToConstant:28]
    ]];
    
    // 创建搜索模式按钮
    NSArray *searchModeConfig = @[
        @{@"title": @"精确", @"action": @"searchTapped", @"color": IMGUI_BUTTON},
        @{@"title": @"模糊", @"action": @"helpTapped", @"color": IMGUI_BUTTON},
        @{@"title": @"特征", @"action": @"signatureTapped", @"color": IMGUI_BUTTON}, // Feature -> Sign (Shorter)
        @{@"title": @"偏移", @"action": @"offsetTapped", @"color": IMGUI_BUTTON}
    ];
    
    // 创建编辑模式按钮
    NSArray *editModeConfig = @[
        @{@"title": @"全选", @"action": @"selectAllTapped", @"color": IMGUI_BUTTON}, // Select All -> All
        @{@"title": @"反选", @"action": @"invertSelectionTapped", @"color": IMGUI_BUTTON},
        @{@"title": @"保存", @"action": @"saveTapped", @"color": IMGUI_BUTTON},
        @{@"title": @"计算", @"action": @"calculateOffsetTapped", @"color": IMGUI_BUTTON} // Calculate -> Calc
    ];
    
    // 创建按钮并存储到数组中
    NSMutableArray *searchButtons = [NSMutableArray array];
    NSMutableArray *editButtons = [NSMutableArray array];
    
    // 创建搜索模式按钮
    for (NSInteger i = 0; i < searchModeConfig.count; i++) {
        NSDictionary *config = searchModeConfig[i];
        UIButton *button = [self createCyberButtonWithTitle:config[@"title"] color:config[@"color"] action:NSSelectorFromString(config[@"action"])];
        
        // 设置按钮大小约束
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:50], // Slightly wider for text
            [button.heightAnchor constraintEqualToConstant:28]
        ]];
        
        [searchButtons addObject:button];
    }
    
    // 创建编辑模式按钮
    for (NSDictionary *config in editModeConfig) {
        UIButton *button = [self createCyberButtonWithTitle:config[@"title"] color:config[@"color"] action:NSSelectorFromString(config[@"action"])];
        
        // 设置按钮大小约束
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:50],
            [button.heightAnchor constraintEqualToConstant:28]
        ]];
        
        [editButtons addObject:button];
        button.hidden = YES;  // 初始隐藏编辑模式按钮
    }
    
    self.searchModeButtons = searchButtons;
    self.editModeButtons = editButtons;
    
    // 将所有按钮添加到工具栏
    for (UIButton *button in searchButtons) {
        [toolbarStack addArrangedSubview:button];
    }
    
    for (UIButton *button in editButtons) {
        [toolbarStack addArrangedSubview:button];
    }
    
    // 创建滑动开关
    UISwitch *modeSwitch = [[UISwitch alloc] init];
    [modeSwitch addTarget:self action:@selector(modeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    modeSwitch.onTintColor = IMGUI_CHECKMARK;
    // Scale down switch slightly to fit
    modeSwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [self.view addSubview:modeSwitch];
    self.modeSwitch = modeSwitch;
    
    // 创建关闭按钮
    UIButton *closeButton = [self createCyberButtonWithTitle:@"关闭" color:IMGUI_BUTTON action:@selector(closeButtonTapped)];
    [self.view addSubview:closeButton];
    
    // 设置关闭按钮约束
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.centerYAnchor constraintEqualToAnchor:toolbarStack.centerYAnchor],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [closeButton.widthAnchor constraintEqualToConstant:60],
        [closeButton.heightAnchor constraintEqualToConstant:28]
    ]];
    
    // 添加分线
    UIView *separatorLine = [[UIView alloc] init];
    separatorLine.backgroundColor = IMGUI_BORDER_COLOR;
    [self.view addSubview:separatorLine];
    
    // 设置分割线约束
    separatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [separatorLine.topAnchor constraintEqualToAnchor:toolbarStack.bottomAnchor constant:5],
        [separatorLine.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [separatorLine.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [separatorLine.heightAnchor constraintEqualToConstant:1.0]
    ]];
    
    // 添加计数标签
    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.text = @"0";
    countLabel.textColor = IMGUI_TEXT;
    countLabel.font = ImGuiFont(14, NO);
    countLabel.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:countLabel];
    
    // 设置计数标签约束
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [countLabel.topAnchor constraintEqualToAnchor:separatorLine.bottomAnchor constant:5],
        [countLabel.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-80],
        [countLabel.heightAnchor constraintEqualToConstant:20]
    ]];
    
    // 保存为属性
    self.countLabel = countLabel;
    
    // 扫描中点头部计数可以取消（进度也显示在这里）
    countLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tapCount = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(countLabelTapped:)];
    [countLabel addGestureRecognizer:tapCount];
    
    [LoggingService log:@"计数标签已创建并配置"];
    
    // 设置滑动开关约束 - 移动到第二行计数标签右边
    modeSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [modeSwitch.centerYAnchor constraintEqualToAnchor:countLabel.centerYAnchor],
        [modeSwitch.leadingAnchor constraintEqualToAnchor:countLabel.trailingAnchor constant:10],
    ]];
    
    // 添加第二条分割线
    UIView *secondSeparatorLine = [[UIView alloc] init];
    secondSeparatorLine.backgroundColor = IMGUI_BORDER_COLOR;
    [self.view addSubview:secondSeparatorLine];
    
    // 设置第二条分割线约束
    secondSeparatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [secondSeparatorLine.topAnchor constraintEqualToAnchor:countLabel.bottomAnchor constant:5],
        [secondSeparatorLine.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [secondSeparatorLine.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [secondSeparatorLine.heightAnchor constraintEqualToConstant:1.0]
    ]];
    
    // 列标题（表头）——地址 / 类型 / HEX / DEC，取代原来"纯靠颜色猜列"
    UILabel *columnHeader = [[UILabel alloc] init];
    columnHeader.attributedText = [self renderHeader];
    columnHeader.backgroundColor = IMGUI_CHILD_BG;
    columnHeader.userInteractionEnabled = NO;
    [self.view addSubview:columnHeader];
    
    columnHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [columnHeader.topAnchor constraintEqualToAnchor:secondSeparatorLine.bottomAnchor],
        [columnHeader.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],
        [columnHeader.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [columnHeader.heightAnchor constraintEqualToConstant:24]
    ]];
    
    // 添加表格视图
    UITableView *tableView = [[UITableView alloc] init];
    tableView.backgroundColor = [UIColor clearColor]; // Transparent to show BG
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    tableView.separatorColor = IMGUI_BORDER_COLOR;
    tableView.separatorInset = UIEdgeInsetsZero; // Full width separator
    tableView.delegate = self;
    tableView.dataSource = self;
    [self.view addSubview:tableView];
    
    // 设置表格视图约束
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:columnHeader.bottomAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    
    // 保存为属性以便后续使用
    self.tableView = tableView;
    
    // 初始化空数据源
    self.dataSource = [NSMutableArray array];
    
    // 更新计数标签
    self.countLabel.text = @"0";
    // 设置搜索回调
    设置搜索回调(searchResultCallback);
    
    // 注册通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleResetSearch:)
                                               name:kResetSearchNotification
                                             object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleSearchStart:)
                                               name:kSearchStartNotification
                                             object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleSearchProgress:)
                                               name:kSearchProgressNotification
                                             object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleSearchFinish:)
                                               name:kSearchFinishNotification
                                             object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleModifyValue:)
                                               name:@"ModifyValueNotification"
                                             object:nil];
    
    // 添加偏移通知监听
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleOffsetApplied:)
                                               name:kOffsetAppliedNotification
                                             object:nil];
    
    // 初始化颜色
    addressColor = IMGUI_TEXT;                                    // White for address
    hexColor = [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:1.0f]; // Gold for Hex
    decimalColor = IMGUI_CHECKMARK;                               // Blue/Checkmark for Decimal
    typeColor = IMGUI_TEXT_DISABLED;                              // Grey for Type
    staticAddrColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.4f alpha:1.0f];  // 绿色 - 静态地址
    dynamicAddrColor = [UIColor colorWithRed:1.0f green:0.6f blue:0.2f alpha:1.0f]; // 橙色 - 动态地址
    
    // 创建专用的后台队列
    self.updateQueue = dispatch_queue_create("com.memoryUpdate.queue", DISPATCH_QUEUE_SERIAL);
    
    // 创建定时器
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 
                                                       target:self 
                                                     selector:@selector(updateMemoryValues) 
                                                     userInfo:nil 
                                                      repeats:YES];
    
    // 将定时器添加到主运行循环
    [[NSRunLoop mainRunLoop] addTimer:self.updateTimer forMode:NSRunLoopCommonModes];
    
    // 初始化选中索引集合
    self.selectedIndexes = [NSMutableSet new];
    
    // 允许多选
    self.tableView.allowsMultipleSelection = YES;
}

- (void)closeButtonTapped { [[FloatingWindow sharedInstance] hide]; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = ImGuiFont(13, NO); // 使用 ImGui 字体
        
        // 添加选中状态的背景视图
        UIView *selectedBackgroundView = [[UIView alloc] init];
        selectedBackgroundView.backgroundColor = IMGUI_BUTTON_ACTIVE;
        cell.selectedBackgroundView = selectedBackgroundView;
        
        // 添加感叹号按钮作为 accessoryView
        UIButton *accessoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [accessoryButton setTitle:@"!" forState:UIControlStateNormal];
        [accessoryButton setTitleColor:[UIColor colorWithRed:1.0f green:0.4f blue:0.4f alpha:1.0f] forState:UIControlStateNormal]; // Reddish
        accessoryButton.titleLabel.font = ImGuiFont(14, YES);
        accessoryButton.frame = CGRectMake(0, 0, 30, 30);
        [accessoryButton addTarget:self action:@selector(accessoryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = accessoryButton;
        
        // 添加长按手势用于复制地址
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
            initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.5;
        longPress.cancelsTouchesInView = YES;
        [cell addGestureRecognizer:longPress];
    }
    
    if (indexPath.row < self.dataSource.count) {
        cell.textLabel.attributedText = [self renderRow:self.dataSource[indexPath.row]];
    }
    
    return cell;
}

// 更新 UITableViewDelegate 方法
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // 如果不在编辑模式（开关关闭），则执行原来的选中行为
    if (!self.modeSwitch.isOn) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        
        if (indexPath.row >= self.dataSource.count) return;
        SSMemoryRecord *rec = self.dataSource[indexPath.row];
        
        // 创建修改弹窗
        SSModifyPopViewController *modifyVC = [SSModifyPopViewController modifyPopViewController];
        modifyVC.dataType = rec.type;
        modifyVC.address = rec.address;
        
        [self addChildViewController:modifyVC];
        [self.view addSubview:modifyVC.view];
        
        modifyVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [modifyVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [modifyVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [modifyVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [modifyVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
        
        [modifyVC didMoveToParentViewController:self];
    } else {
        // 在编辑模式下，添加到选中集合
        [self.selectedIndexes addObject:@(indexPath.row)];
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    // 如果在编辑模式下，从选中集合中移除
    if (self.modeSwitch.isOn) {
        [self.selectedIndexes removeObject:@(indexPath.row)];
    }
}

// 设置单元格高度
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 34.0;
}

#pragma mark - 行渲染（统一从模型派生，不再存拼串）

- (NSAttributedString *)renderHeader {
    NSString *text = @"地址          类型   HEX        DEC";
    return [[NSAttributedString alloc] initWithString:text
                                           attributes:@{NSForegroundColorAttributeName: IMGUI_TEXT_DISABLED,
                                                        NSFontAttributeName: ImGuiFont(12, YES)}];
}

- (NSAttributedString *)renderRow:(SSMemoryRecord *)rec {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSDictionary *addrAttr = @{NSForegroundColorAttributeName: addressColor};
    NSDictionary *typeAttr = @{NSForegroundColorAttributeName: typeColor};
    NSDictionary *hexAttr  = @{NSForegroundColorAttributeName: hexColor};
    NSDictionary *decAttr  = @{NSForegroundColorAttributeName: decimalColor};
    
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@    ", rec.addressString] attributes:addrAttr]];
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@    ", rec.typeString] attributes:typeAttr]];
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@    ", rec.hexValueString] attributes:hexAttr]];
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:rec.decimalValueString attributes:decAttr]];
    
    return result;
}

- (void)handleResetSearch:(NSNotification *)notification {
    [LoggingService log:@"收到重置搜索通知"];
    
    // 清空数据源
    [self.dataSource removeAllObjects];
    [self.selectedIndexes removeAllObjects];
    
    // 置数标签
    self.countLabel.text = @"0";
    
    // 刷新表格
    [self.tableView reloadData];
    
    [LoggingService log:@"表格数据已清空"];
}

- (void)handleModifyValue:(NSNotification *)notification {
    [LoggingService log:@"收到修改通知，立即刷新一次值"];
    // 值已被外部改写，触发一次差异刷新即可反映到列表
    [self updateMemoryValues];
}

- (void)updateSearchResults:(NSArray *)addresses withType:(SearchDataType)type {
    [self updateSearchResults:addresses totalCount:addresses.count withType:type];
}

- (void)updateSearchResults:(NSArray *)addresses totalCount:(size_t)totalCount withType:(SearchDataType)type {
    [LoggingService log:@"开始更新搜索结果 - 回传: %lu, 总计: %zu, 类型: %d", (unsigned long)addresses.count, totalCount, type];
    
    // 清空现有数据
    [self.dataSource removeAllObjects];
    [self.selectedIndexes removeAllObjects];
    
    // 限制处理的数量为150
    NSInteger maxResults = 150;
    NSArray *limitedAddresses = addresses.count > maxResults ?
        [addresses subarrayWithRange:NSMakeRange(0, maxResults)] : addresses;
    
    size_t width = [SSDataTypeUtility widthForType:type];
    
    // 遍历地址，读取当前值并构建统一模型
    for (NSNumber *address in limitedAddresses) {
        uint64_t addr = [address unsignedLongLongValue];
        uint64_t value = 0;
        
        // 按类型宽度读：u8/i16/i32 在区域末尾读 8 字节会失败
        size_t outsize = 0;
        if (!SSMemoryRead(addr, &value, width, &outsize) || outsize != width) {
            value = 0;
        }
        
        SSMemoryRecord *rec = [[SSMemoryRecord alloc] init];
        rec.address = addr;
        rec.type = type;
        rec.lastValue = value;
        [self.dataSource addObject:rec];
    }
    
    if (addresses.count > maxResults) {
        [LoggingService log:@"搜索结果超过显示限制，仅显示前 %ld 条，总计: %lu", (long)maxResults, (unsigned long)addresses.count];
    }
    
    // 更新计数标签
    dispatch_async(dispatch_get_main_queue(), ^{
        // 模糊搜索初始化状态判断：模式二 + 命中 0 + 结果文件路径为空（仅有快照）
        if (当前搜索模式 == 模式二 && totalCount == 0 && search_results && search_results->result_file_path == NULL) {
            self.countLabel.text = @"模糊初始化";
        } else if ([ScannerState shared].resultTruncated) {
            self.countLabel.text = [NSString stringWithFormat:@"%lu+", (unsigned long)totalCount];
        } else {
            self.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)totalCount];
        }
        [LoggingService log:@"计数标签已更新为: %@", self.countLabel.text];
        
        [self.tableView reloadData];
    });
}

// 每秒刷新可见行的值：只更新"真的变了"的行，并合并成一次主线程提交
- (void)updateMemoryValues {
    if (self.dataSource.count == 0) return;
    
    NSArray<SSMemoryRecord *> *快照 = [self.dataSource copy];   // 主线程取快照
    
    dispatch_async(self.updateQueue, ^{
        NSMutableArray *变更行 = [NSMutableArray array];
        NSMutableArray *变更文本 = [NSMutableArray array];
        NSMutableArray *变更原始 = [NSMutableArray array];
        
        for (NSUInteger i = 0; i < 快照.count; i++) {
            SSMemoryRecord *rec = 快照[i];
            size_t width = [SSDataTypeUtility widthForType:rec.type];
            
            uint64_t value = 0;
            size_t outsize = 0;
            if (!SSMemoryRead(rec.address, &value, width, &outsize) || outsize != width) {
                continue;   // 读不到就保持原样
            }
            if (value == rec.lastValue) continue;   // 没变不刷新
            
            [变更行 addObject:@(i)];
            [变更文本 addObject:[self renderRow:rec withValue:value]];   // 用新值渲染，但先不改 rec
            [变更原始 addObject:@(value)];
        }
        
        if (变更行.count == 0) return;
        
        NSUInteger 条数 = 变更行.count;
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSUInteger k = 0; k < 条数; k++) {
                NSUInteger idx = [变更行[k] unsignedIntegerValue];
                if (idx >= self.dataSource.count) continue;
                SSMemoryRecord *rec = self.dataSource[idx];
                rec.lastValue = [变更原始[k] unsignedLongLongValue];   // 提交新值到模型
                
                NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:0];
                UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
                if (cell.textLabel) cell.textLabel.attributedText = 变更文本[k];
            }
        });
    });
}

// 用给定（尚未提交到模型的）原始值渲染一行，供后台差异计算使用
- (NSAttributedString *)renderRow:(SSMemoryRecord *)rec withValue:(uint64_t)value {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSString *hex = [SSDataTypeUtility hexStringForValue:value type:rec.type];
    NSString *dec = [SSDataTypeUtility decimalStringForValue:value type:rec.type];
    
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@    ", rec.addressString]
            attributes:@{NSForegroundColorAttributeName: addressColor}]];
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@    ", rec.typeString]
            attributes:@{NSForegroundColorAttributeName: typeColor}]];
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@    ", hex]
            attributes:@{NSForegroundColorAttributeName: hexColor}]];
    [result appendAttributedString:[[NSAttributedString alloc]
        initWithString:dec attributes:@{NSForegroundColorAttributeName: decimalColor}]];
    return result;
}

#pragma mark - 记录页回跳定位

- (void)focusAddress:(uint64_t)address {
    NSUInteger found = NSNotFound;
    for (NSUInteger i = 0; i < self.dataSource.count; i++) {
        SSMemoryRecord *rec = self.dataSource[i];
        if (!rec.isPointerChain && rec.address == address) { found = i; break; }
    }
    
    if (found == NSNotFound) {
        [LoggingService log:@"回跳定位失败：当前搜索结果不含 0x%llX", (unsigned long long)address];
        self.countLabel.text = [NSString stringWithFormat:@"未找到 0x%llX", (unsigned long long)address];
        return;
    }
    
    NSIndexPath *ip = [NSIndexPath indexPathForRow:found inSection:0];
    [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    [self.tableView selectRowAtIndexPath:ip animated:YES scrollPosition:UITableViewScrollPositionMiddle];
    
    [LoggingService log:@"回跳定位成功：0x%llX 第 %lu 行", (unsigned long long)address, (unsigned long)found];
}

#pragma mark - 后台扫描状态

- (void)handleSearchStart:(NSNotification *)notification {
    self.countLabel.text = @"扫描中 0%";
}

- (void)handleSearchProgress:(NSNotification *)notification {
    double 进度 = [notification.userInfo[@"progress"] doubleValue];
    self.countLabel.text = [NSString stringWithFormat:@"扫描中 %.0f%%", 进度 * 100.0];
}

- (void)handleSearchFinish:(NSNotification *)notification {
    if ([notification.userInfo[@"cancelled"] boolValue]) {
        self.countLabel.text = @"已取消";
    }
    // 正常结束时由结果回调更新计数
}

- (void)countLabelTapped:(UITapGestureRecognizer *)gesture {
    if (是否正在扫描()) {
        取消搜索();
        self.countLabel.text = @"正在取消…";
    }
}

// 在 dealloc 中清理定时器
- (void)dealloc {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 添加暂停和恢复更新的方法
- (void)pauseUpdates {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

- (void)resumeUpdates {
    if (!self.updateTimer) {
        self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 
                                                           target:self 
                                                         selector:@selector(updateMemoryValues) 
                                                         userInfo:nil 
                                                          repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.updateTimer forMode:NSRunLoopCommonModes];
    }
}

// 添加视图将要消失时暂停更新
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pauseUpdates];
}

// 添加视图将要出现时恢复更新
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self resumeUpdates];
}

@end
