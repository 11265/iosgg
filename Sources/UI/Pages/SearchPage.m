// 系统框架
#import <mach/mach.h>
#import <mach-o/dyld.h>

// 自定义视图控制器
#import "UI/Pages/SearchPage.h"
#import "UI/Dialogs/EditValueDialog.h"
#import "UI/Dialogs/CompareDialog.h"
#import "UI/Dialogs/OffsetDialog.h"
#import "UI/Dialogs/SignatureDialog.h"
#import "UI/Pages/TracePage.h"
#import "UI/Dialogs/FuzzySearchDialog.h"
#import "UI/Dialogs/RegisterStateDialog.h"
#import "UI/Dialogs/SearchDialog.h"
#import "UI/Pages/RecordPage.h"

// 工具类
#import "Services/LogService.h"
#import "Services/ProcessMemory.h"
#import "External/lz4/lz4.h"

#import "UI/Components/ThemeConfig.h"
#import "UI/Pages/SearchPage+Actions.h"

// 在文件开头添加回调函数定义
static void searchResultCallback(uint64_t* results, size_t count, SearchDataType type) {
    [LoggingService log:@"搜索回调被触发 - 结果数量: %zu, 类型: %d", count, type];
    
    SearchPage *searchVC = [FloatingWindow sharedInstance].searchViewController;
    if (!searchVC) {
        [LoggingService log:@"错误：无法获取搜索视图控制器实例"];
        return;
    }
    
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        [addresses addObject:@(results[i])];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [searchVC updateSearchResults:addresses withType:type];
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
        [tableView.topAnchor constraintEqualToAnchor:secondSeparatorLine.bottomAnchor],
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
    //[LoggingService log:@"配置第 %ld 行的单元格", (long)indexPath.row];
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
    
    cell.textLabel.attributedText = self.dataSource[indexPath.row];
    
    return cell;
}

// 更新 UITableViewDelegate 方法
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // 如果不在编辑模式（开关关闭），则执行原来的选中行为
    if (!self.modeSwitch.isOn) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        
        // 获取选中行的富文本
        NSAttributedString *rowText = self.dataSource[indexPath.row];
        NSString *plainText = rowText.string;
        
        // 解析地址 - 从文本中提取地址部分
        NSArray *components = [plainText componentsSeparatedByString:@"    "];
        if (components.count == 0) {
            [LoggingService log:@"错误：无法解析文本"];
            return;
        }
        
        NSString *addressPart = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        uint64_t address = 0;
        NSScanner *scanner = [NSScanner scannerWithString:addressPart];
        if (![scanner scanHexLongLong:&address]) {
            [LoggingService log:@"错误：无法解析地址: %@", addressPart];
            return;
        }
        
        // 解析类型
        NSString *typeStr = nil;
        if (components.count >= 2) {
            typeStr = components[1];
        }
        
        SearchDataType dataType;
        if ([typeStr isEqualToString:@"i32"]) {
            dataType = SearchDataTypeI32;
        } else if ([typeStr isEqualToString:@"i64"]) {
            dataType = SearchDataTypeI64;
        } else if ([typeStr isEqualToString:@"f32"]) {
            dataType = SearchDataTypeF32;
        } else if ([typeStr isEqualToString:@"f64"]) {
            dataType = SearchDataTypeF64;
        } else if ([typeStr isEqualToString:@"ptr"]) {
            dataType = SearchDataTypePtr;
        } else {
            dataType = SearchDataTypeI32;
        }
        
        // 创建修改弹窗
        SSModifyPopViewController *modifyVC = [SSModifyPopViewController modifyPopViewController];
        modifyVC.dataType = dataType;
        modifyVC.address = address;
        
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

- (NSAttributedString *)formatResultWithAddress:(uint64_t)addr 
                                      hexValue:(NSString *)hexValue 
                                  decimalValue:(NSString *)decimalValue 
                                         type:(NSString *)type {
    
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    // 地址部分
    NSString *addrDisplayStr = [NSString stringWithFormat:@"0x%llX    ", addr];
    NSAttributedString *addrStr = [[NSAttributedString alloc] 
        initWithString:addrDisplayStr
        attributes:@{NSForegroundColorAttributeName: addressColor}];
    [result appendAttributedString:addrStr];
    
    // 类型部分
    NSAttributedString *typeStr = [[NSAttributedString alloc] 
        initWithString:[NSString stringWithFormat:@"%@    ", type]
        attributes:@{NSForegroundColorAttributeName: typeColor}];
    [result appendAttributedString:typeStr];
    
    // 十六进制值部分
    NSAttributedString *hexStr = [[NSAttributedString alloc] 
        initWithString:[NSString stringWithFormat:@"%@    ", hexValue]
        attributes:@{NSForegroundColorAttributeName: hexColor}];
    [result appendAttributedString:hexStr];
    
    // 十进制值部分
    NSAttributedString *decStr = [[NSAttributedString alloc] 
        initWithString:decimalValue
        attributes:@{NSForegroundColorAttributeName: decimalColor}];
    [result appendAttributedString:decStr];
    
    return result;
}

- (void)handleResetSearch:(NSNotification *)notification {
    [LoggingService log:@"收到重置搜索通知"];
    
    // 清空数据源
    [self.dataSource removeAllObjects];
    
    // 置数标签
    self.countLabel.text = @"0";
    
    // 刷新表格
    [self.tableView reloadData];
    
    [LoggingService log:@"表格数据已清空"];
}

- (void)handleModifyValue:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    uint64_t address = [userInfo[@"address"] unsignedLongLongValue];
    NSString *newValue = userInfo[@"newValue"];
    NSInteger type = [userInfo[@"type"] integerValue];
    
    [LoggingService log:@"收到修改通知 - 地址: 0x%llX, 新值: %@, 类型: %ld", address, newValue, (long)type];
    
    // 从当前显示的结果中提取地址
    NSMutableArray *currentAddresses = [NSMutableArray array];
    for (NSAttributedString *attrStr in self.dataSource) {
        NSString *plainText = attrStr.string;
        NSScanner *scanner = [NSScanner scannerWithString:plainText];
        uint64_t addr;
        if ([scanner scanHexLongLong:&addr]) {
            [currentAddresses addObject:@(addr)];
        }
    }
    
    // 刷新显示
    [self updateSearchResults:currentAddresses withType:type];
}

- (void)updateSearchResults:(NSArray *)addresses withType:(SearchDataType)type {
    [LoggingService log:@"开始更新搜索结果 - 地址数量: %lu, 类型: %d", (unsigned long)addresses.count, type];
    
    // 清空现有数据
    [self.dataSource removeAllObjects];
    
    // 限制处理的数量为150
    NSInteger maxResults = 150;
    NSArray *limitedAddresses = addresses.count > maxResults ? 
        [addresses subarrayWithRange:NSMakeRange(0, maxResults)] : addresses;
    
    [LoggingService log:@"限制显示数量为 %ld，实际处理数量: %lu", (long)maxResults, (unsigned long)limitedAddresses.count];
    
    // 遍历地址并读取值
    NSInteger successCount = 0;
    NSInteger failCount = 0;
    
    for (NSNumber *address in limitedAddresses) {
        uint64_t addr = [address unsignedLongLongValue];
        uint64_t value;  // 添加变量声明
        
        // 使用mach_vm_read_overwrite读取内存
        mach_vm_size_t size = sizeof(uint64_t);
        mach_vm_address_t targetAddress = addr;
        mach_vm_size_t outsize;
        mach_vm_read_overwrite(mach_task_self(), targetAddress, size, (mach_vm_address_t)&value, &outsize);
        
        NSAttributedString *resultString;
        NSString *hexValue;
        NSString *decimalValue;
        NSString *typeStr;
        
        // 添加日志跟踪每个地址的处理
        //[LoggingService log:@"处理地址: 0x%llX, 读取值: 0x%llX", addr, value];
        
        switch(type) {
            case SearchDataTypeU8: {
                uint8_t uint8Value = (uint8_t)value;
                hexValue = [NSString stringWithFormat:@"%02X", uint8Value];
                decimalValue = [NSString stringWithFormat:@"%u", uint8Value];
                typeStr = @"u8";
                break;
            }
            case SearchDataTypeI16: {
                int16_t int16Value = (int16_t)value;
                hexValue = [NSString stringWithFormat:@"%04X", (uint16_t)int16Value];
                decimalValue = [NSString stringWithFormat:@"%d", int16Value];
                typeStr = @"i16";
                break;
            }
            case SearchDataTypeI32: {
                int32_t int32Value = (int32_t)value;
                hexValue = [NSString stringWithFormat:@"%08X", int32Value];
                decimalValue = [NSString stringWithFormat:@"%d", int32Value];
                typeStr = @"i32";
                break;
            }
            case SearchDataTypeI64: {
                int64_t int64Value = (int64_t)value;
                hexValue = [NSString stringWithFormat:@"%016llX", int64Value];
                decimalValue = [NSString stringWithFormat:@"%lld", int64Value];
                typeStr = @"i64";
                break;
            }
            case SearchDataTypeF32: {
                float floatValue = *(float*)&value;
                hexValue = [NSString stringWithFormat:@"%08X", *(uint32_t*)&floatValue];
                decimalValue = [NSString stringWithFormat:@"%f", floatValue];
                typeStr = @"f32";
                break;
            }
            case SearchDataTypeF64: {
                double doubleValue = *(double*)&value;
                hexValue = [NSString stringWithFormat:@"%016llX", value];
                decimalValue = [NSString stringWithFormat:@"%lf", doubleValue];
                typeStr = @"f64";
                break;
            }
            case SearchDataTypePtr: {
                hexValue = [NSString stringWithFormat:@"%016llX", value];
                decimalValue = [NSString stringWithFormat:@"0x%llX", value];
                typeStr = @"ptr";
                break;
            }
            default:
                hexValue = @"";
                decimalValue = @"";
                typeStr = @"";
        }
        
        resultString = [self formatResultWithAddress:addr 
                                          hexValue:hexValue 
                                      decimalValue:decimalValue 
                                             type:typeStr];
        
        [self.dataSource addObject:resultString];
        successCount++;
    }
    
    // 如果原始数据超过限制，日志中记录
    if (addresses.count > maxResults) {
        [LoggingService log:@"搜索结果超过显示限制，仅显示前 %ld 条，总计: %lu", (long)maxResults, (unsigned long)addresses.count];
    }
    
    [LoggingService log:@"搜索结果处理完成 - 成功: %ld, 失败: %ld", (long)successCount, (long)failCount];
    
    // 更新计数标签
    dispatch_async(dispatch_get_main_queue(), ^{
        // 模糊搜索初始化状态判断：
        // 1. 模式为模式二
        // 2. 结果数量为0
        // 3. 结果文件路径为空 (result_file_path == NULL 表示尚未生成筛选结果，仅有快照)
        if (当前搜索模式 == 模式二 && addresses.count == 0 && search_results && search_results->result_file_path == NULL) {
             self.countLabel.text = @"模糊初始化";
        } else {
             self.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)addresses.count];
        }
        [LoggingService log:@"计数标签已更新为: %@", self.countLabel.text];
    });
    
    // 刷新表格
    dispatch_async(dispatch_get_main_queue(), ^{
        [LoggingService log:@"准备刷新表格，数据源数量: %lu", (unsigned long)self.dataSource.count];
        [self.tableView reloadData];
        [LoggingService log:@"表格刷新完成"];
    });
}

// 修改 updateMemoryValues 方法
- (void)updateMemoryValues {
    // 如果没有数据，直接返回
    if (self.dataSource.count == 0) return;
    
    // 在后台队列中处理更新
    dispatch_async(self.updateQueue, ^{
        for (NSUInteger i = 0; i < self.dataSource.count; i++) {
            NSAttributedString *attrStr = self.dataSource[i];
            NSString *plainText = attrStr.string;
            
            // 解析地址和类型
            NSArray *components = [plainText componentsSeparatedByString:@"    "];
            if (components.count < 4) continue;
            
            // 获取地址
            NSString *addrStr = components[0];
            uint64_t addr;
            NSScanner *scanner = [NSScanner scannerWithString:addrStr];
            if (![scanner scanHexLongLong:&addr]) continue;
            
            // 获取类型
            NSString *typeStr = components[1];
            SearchDataType type;
            
            if ([typeStr isEqualToString:@"i32"]) {
                type = SearchDataTypeI32;
            } else if ([typeStr isEqualToString:@"i64"]) {
                type = SearchDataTypeI64;
            } else if ([typeStr isEqualToString:@"f32"]) {
                type = SearchDataTypeF32;
            } else if ([typeStr isEqualToString:@"f64"]) {
                type = SearchDataTypeF64;
            } else if ([typeStr isEqualToString:@"ptr"]) {
                type = SearchDataTypePtr;
            } else {
                continue;
            }
            
            // 读取新的内存值
            uint64_t value;  // 添加变量声明
            mach_vm_size_t size = sizeof(uint64_t);
            mach_vm_address_t targetAddress = addr;
            mach_vm_size_t outsize;
            mach_vm_read_overwrite(mach_task_self(), targetAddress, size, (mach_vm_address_t)&value, &outsize);
            
            NSString *hexValue;
            NSString *decimalValue;
            
            switch(type) {
                case SearchDataTypeU8: {
                    uint8_t uint8Value = (uint8_t)value;
                    hexValue = [NSString stringWithFormat:@"%02X", uint8Value];
                    decimalValue = [NSString stringWithFormat:@"%u", uint8Value];
                    break;
                }
                case SearchDataTypeI16: {
                    int16_t int16Value = (int16_t)value;
                    hexValue = [NSString stringWithFormat:@"%04X", (uint16_t)int16Value];
                    decimalValue = [NSString stringWithFormat:@"%d", int16Value];
                    break;
                }
                case SearchDataTypeI32: {
                    int32_t int32Value = (int32_t)value;
                    hexValue = [NSString stringWithFormat:@"%08X", int32Value];
                    decimalValue = [NSString stringWithFormat:@"%d", int32Value];
                    break;
                }
                case SearchDataTypeI64: {
                    int64_t int64Value = (int64_t)value;
                    hexValue = [NSString stringWithFormat:@"%016llX", int64Value];
                    decimalValue = [NSString stringWithFormat:@"%lld", int64Value];
                    break;
                }
                case SearchDataTypeF32: {
                    float floatValue = *(float*)&value;
                    hexValue = [NSString stringWithFormat:@"%08X", *(uint32_t*)&floatValue];
                    decimalValue = [NSString stringWithFormat:@"%f", floatValue];
                    break;
                }
                case SearchDataTypeF64: {
                    double doubleValue = *(double*)&value;
                    hexValue = [NSString stringWithFormat:@"%016llX", value];
                    decimalValue = [NSString stringWithFormat:@"%lf", doubleValue];
                    break;
                }
                case SearchDataTypePtr: {
                    hexValue = [NSString stringWithFormat:@"%016llX", value];
                    decimalValue = [NSString stringWithFormat:@"0x%llX", value];
                    break;
                }
            }
            
            // 创建新的富文本字符串
            NSMutableAttributedString *newResult = [[NSMutableAttributedString alloc] init];
            
            // 添加地址部分（保持原样）
            [newResult appendAttributedString:[[NSAttributedString alloc] 
                initWithString:[NSString stringWithFormat:@"%@    ", addrStr]
                attributes:@{NSForegroundColorAttributeName: addressColor}]];
            
            // 添加类型部分（保持原样）
            [newResult appendAttributedString:[[NSAttributedString alloc] 
                initWithString:[NSString stringWithFormat:@"%@    ", typeStr]
                attributes:@{NSForegroundColorAttributeName: typeColor}]];
            
            // 添加新的十六进制值
            [newResult appendAttributedString:[[NSAttributedString alloc] 
                initWithString:[NSString stringWithFormat:@"%@    ", hexValue]
                attributes:@{NSForegroundColorAttributeName: hexColor}]];
            
            // 添加新的十进制值
            [newResult appendAttributedString:[[NSAttributedString alloc] 
                initWithString:decimalValue
                attributes:@{NSForegroundColorAttributeName: decimalColor}]];
            
            // 在主线程更新UI
            dispatch_async(dispatch_get_main_queue(), ^{
                self.dataSource[i] = newResult;
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
                UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                if (cell && cell.textLabel) {
                    cell.textLabel.attributedText = newResult;
                }
            });
        }
    });
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