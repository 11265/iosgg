#import "UI/Pages/Debugger/TracePage.h"
#import "UI/Pages/Debugger/TracePage+Private.h"
#import "UI/Pages/Debugger/TracePage+Debugger.h"
#import "Services/LogService.h"
#import "Modules/Debugger/SSDebugger.h"
#import <objc/runtime.h>
#import "UI/Components/FloatingWindow.h"
#import "UI/Pages/Scanner/SearchPage.h"
#import "UI/Pages/Memory/MemoryPage.h"
#import "UI/Dialogs/RegisterStateDialog.h"

// 先声明 SSCopyMenuView 类
@interface SSCopyMenuView : UIView

@property (nonatomic, copy) void (^onCopyInstruction)(void);
@property (nonatomic, copy) void (^onCopyWatch)(void);
@property (nonatomic, copy) void (^onViewInstruction)(void);

- (void)showInView:(UIView *)view fromRect:(CGRect)rect;
- (void)dismiss;

@end

@implementation SSTrackRecord
@end

@interface SSTrackCell : UITableViewCell
@property (nonatomic, strong) UILabel *mainLabel;
@property (nonatomic, strong) UILabel *detailLabel;
// 修改按钮属性，删除watchButton
@property (nonatomic, strong) UIButton *instructionButton;
@property (nonatomic, strong) UIButton *viewButton;
@property (nonatomic, copy) void (^onCopyInstruction)(void);
@property (nonatomic, copy) void (^onViewInstruction)(void);
@property (nonatomic, strong) UIButton *registerButton;
@property (nonatomic, copy) void (^onRegisterTapped)(void);
@end

@implementation SSTrackCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        // 创建主标签
        self.mainLabel = [[UILabel alloc] init];
        self.mainLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.mainLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        [self.contentView addSubview:self.mainLabel];
        
        // 创建详情标签
        self.detailLabel = [[UILabel alloc] init];
        self.detailLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        self.detailLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        [self.contentView addSubview:self.detailLabel];
        
        // 创建复制指令按钮
        self.instructionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.instructionButton setTitle:@"复制指令地址" forState:UIControlStateNormal];
        [self.instructionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.instructionButton.titleLabel.font = [UIFont systemFontOfSize:12];
        self.instructionButton.backgroundColor = [UIColor systemBlueColor];
        [self.instructionButton addTarget:self action:@selector(copyInstructionTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.instructionButton];
        
        // 创建查看指令按钮
        self.viewButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.viewButton setTitle:@"查看指令" forState:UIControlStateNormal];
        [self.viewButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.viewButton.titleLabel.font = [UIFont systemFontOfSize:12];
        self.viewButton.backgroundColor = [UIColor systemOrangeColor];
        [self.viewButton addTarget:self action:@selector(viewInstructionTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.viewButton];
        
        // 添加寄存器按钮
        self.registerButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.registerButton setTitle:@"寄存器" forState:UIControlStateNormal];
        [self.registerButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.registerButton.titleLabel.font = [UIFont systemFontOfSize:12];
        self.registerButton.backgroundColor = [UIColor systemPurpleColor];
        [self.registerButton addTarget:self action:@selector(registerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.registerButton];
        
        // 设置约束
        self.mainLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.instructionButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.viewButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.registerButton.translatesAutoresizingMaskIntoConstraints = NO;
        
        CGFloat buttonWidth = 80; // 增加按钮宽度，因为现在只有两个按钮
        CGFloat buttonHeight = 35;
        
        [NSLayoutConstraint activateConstraints:@[
            // 主标签约束
            [self.mainLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [self.mainLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [self.mainLabel.trailingAnchor constraintEqualToAnchor:self.registerButton.leadingAnchor constant:-8],
            
            // 详情标签约束
            [self.detailLabel.topAnchor constraintEqualToAnchor:self.mainLabel.bottomAnchor constant:2],
            [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.registerButton.leadingAnchor constant:-8],
            [self.detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            
            // 寄存器按钮约束 - 放在复制指令按钮左边
            [self.registerButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.registerButton.trailingAnchor constraintEqualToAnchor:self.instructionButton.leadingAnchor constant:-8],
            [self.registerButton.widthAnchor constraintEqualToConstant:buttonWidth],
            [self.registerButton.heightAnchor constraintEqualToConstant:buttonHeight],
            
            // 复制指令按钮约束
            [self.instructionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.instructionButton.trailingAnchor constraintEqualToAnchor:self.viewButton.leadingAnchor constant:-8],
            [self.instructionButton.widthAnchor constraintEqualToConstant:buttonWidth],
            [self.instructionButton.heightAnchor constraintEqualToConstant:buttonHeight],
            
            // 查看指令按钮约束
            [self.viewButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.viewButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [self.viewButton.widthAnchor constraintEqualToConstant:buttonWidth],
            [self.viewButton.heightAnchor constraintEqualToConstant:buttonHeight],
        ]];
    }
    return self;
}

- (void)copyInstructionTapped {
    if (self.onCopyInstruction) {
        self.onCopyInstruction();
    }
}

- (void)viewInstructionTapped {
    if (self.onViewInstruction) {
        self.onViewInstruction();
    }
}

- (void)registerTapped {
    if (self.onRegisterTapped) {
        self.onRegisterTapped();
    }
}

@end

@implementation SSTrackPopViewController

+ (instancetype)trackPopViewController {
    return [self sharedInstance];
}

- (instancetype)init {
    if (self = [super init]) {
        _isDebugging = NO;
        _trackingData = [NSMutableArray array];
        _watchAddresses = [NSMutableArray array];
        
        // 在初始化时就注册通知，确保无论视图是否加载都能同步状态
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDebuggerStateChanged:) name:kSSDebuggerStateChangedNotification object:nil];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 修改背景颜色为半透明灰色,与MemoryPages一致
    self.view.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    
    // 添加关闭按钮
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    
    // 创建清除按钮
    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearButton setTitle:@"清除" forState:UIControlStateNormal];
    [self.clearButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearButton.backgroundColor = [UIColor systemGreenColor];
    [self.clearButton addTarget:self action:@selector(clearButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.clearButton];
    
    // 建地址输入框
    self.addressField = [[UITextField alloc] init];
    self.addressField.placeholder = @"请输入内存地址";
    self.addressField.backgroundColor = [UIColor whiteColor];
    self.addressField.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.addressField];
    
    // 创建监视按钮
    self.watchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.watchButton setTitle:@"监视" forState:UIControlStateNormal];
    [self.watchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.watchButton.backgroundColor = [UIColor systemBlueColor];
    [self.watchButton addTarget:self action:@selector(watchButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.watchButton];
    
    // 创建启动调试器按钮
    self.startDebugButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startDebugButton setTitle:@"启动" forState:UIControlStateNormal];
    [self.startDebugButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startDebugButton.backgroundColor = [UIColor systemGreenColor];
    [self.startDebugButton addTarget:self action:@selector(startButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startDebugButton];
    
    // 创建停止调试器按钮
    self.stopDebugButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopDebugButton setTitle:@"停止" forState:UIControlStateNormal];
    [self.stopDebugButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.stopDebugButton.backgroundColor = [UIColor systemOrangeColor];
    [self.stopDebugButton addTarget:self action:@selector(stopButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopDebugButton];
    
    // 在stopDebugButton后添加清空按钮
    UIButton *clearInputButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearInputButton setTitle:@"清空" forState:UIControlStateNormal];
    [clearInputButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearInputButton.backgroundColor = [UIColor systemOrangeColor];
    [clearInputButton addTarget:self action:@selector(clearInputButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:clearInputButton];
    
    // 设置约束
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressField.translatesAutoresizingMaskIntoConstraints = NO;
    self.watchButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.startDebugButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.stopDebugButton.translatesAutoresizingMaskIntoConstraints = NO;
    clearInputButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 关闭按钮约束
        [closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:5],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [closeButton.widthAnchor constraintEqualToConstant:60],
        [closeButton.heightAnchor constraintEqualToConstant:35],
        
        // 清空按钮约束 (原清除按钮位置)
        [clearInputButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [clearInputButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [clearInputButton.widthAnchor constraintEqualToConstant:60],
        [clearInputButton.heightAnchor constraintEqualToConstant:35],
        
        // 输入框约束
        [self.addressField.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [self.addressField.leadingAnchor constraintEqualToAnchor:clearInputButton.trailingAnchor constant:10],
        [self.addressField.widthAnchor constraintEqualToConstant:160],
        [self.addressField.heightAnchor constraintEqualToConstant:35],
        
        // 监视按钮约束
        [self.watchButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [self.watchButton.leadingAnchor constraintEqualToAnchor:self.addressField.trailingAnchor constant:10],
        [self.watchButton.widthAnchor constraintEqualToConstant:60],
        [self.watchButton.heightAnchor constraintEqualToConstant:35],
        
        // 启动按钮约束
        [self.startDebugButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [self.startDebugButton.leadingAnchor constraintEqualToAnchor:self.watchButton.trailingAnchor constant:10],
        [self.startDebugButton.widthAnchor constraintEqualToConstant:60],
        [self.startDebugButton.heightAnchor constraintEqualToConstant:35],
        
        // 停止按钮约束
        [self.stopDebugButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [self.stopDebugButton.leadingAnchor constraintEqualToAnchor:self.startDebugButton.trailingAnchor constant:10],
        [self.stopDebugButton.widthAnchor constraintEqualToConstant:60],
        [self.stopDebugButton.heightAnchor constraintEqualToConstant:35],
        
        // 清除按钮约束 (原清空按钮位置)
        [self.clearButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [self.clearButton.leadingAnchor constraintEqualToAnchor:self.stopDebugButton.trailingAnchor constant:10],
        [self.clearButton.widthAnchor constraintEqualToConstant:60],
        [self.clearButton.heightAnchor constraintEqualToConstant:35],
    ]];
    
    // 创建表格视图
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor lightGrayColor];
    self.tableView.showsVerticalScrollIndicator = YES;
    [self.tableView registerClass:[SSTrackCell class] forCellReuseIdentifier:@"TrackCell"];
    [self.view addSubview:self.tableView];
    
    // 设置表格视图约束
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    // 更新按钮状态
    [self updateButtonStates];
    
    // 注册调试器状态变更通知
    // [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDebuggerStateChanged:) name:kSSDebuggerStateChangedNotification object:nil];
}

- (void)handleDebuggerStateChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isDebugging = [SSDebugger sharedInstance].isDebugging;
        [self updateButtonStates];
    });
}

- (void)closeButtonTapped {
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        self.view.hidden = YES;
        self.view.alpha = 1;
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.trackingData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"TrackCell";
    SSTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (!cell) {
        cell = [[SSTrackCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    // 获取记录
    SSTrackRecord *record = self.trackingData[indexPath.row];
    
    if (record.instructionAddr == 0) {
        // 这是监视地址
        cell.mainLabel.text = [NSString stringWithFormat:@"监视 0x%llx", record.address];
        cell.mainLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; // 金黄色
        cell.detailLabel.text = @""; // 不显示等待触发的文本
        
        // 隐藏所有按钮
        cell.instructionButton.hidden = YES;
        cell.viewButton.hidden = YES;
        cell.registerButton.hidden = YES;
    } else {
        // 这是触发记录
        cell.mainLabel.text = [NSString stringWithFormat:@"0x%llx = 0x%llx %ld次", 
                             record.address, record.value, (long)record.hitCount];
        cell.mainLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0]; // 默认颜色
        
        NSString *typeStr = @"未知";
        if (record.type == SSBreakpointTypeWrite) typeStr = @"写入";
        else if (record.type == SSBreakpointTypeRead) typeStr = @"读取";
        else if (record.type == SSBreakpointTypeExecute) typeStr = @"执行";
        cell.detailLabel.text = [NSString stringWithFormat:@"指令地址: 0x%llx  类型: %@", 
                                record.instructionAddr, typeStr];
        
        // 显示所有按钮
        cell.instructionButton.hidden = NO;
        cell.viewButton.hidden = NO;
        cell.registerButton.hidden = NO;
        
        // 设置按钮回调
        cell.onCopyInstruction = ^{
            NSString *addressString = [NSString stringWithFormat:@"0x%llx", record.instructionAddr];
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            pasteboard.string = addressString;
            [LoggingService log:@"已复制指令地址: %@", addressString];
        };
        
        cell.onViewInstruction = ^{
            FloatingWindow *floatingWindow = [FloatingWindow sharedInstance];
            MemoryPages *memoryVC = floatingWindow.memoryViewController;
            if (memoryVC) {
                floatingWindow.tabBarController.selectedIndex = 2;
                
                if (floatingWindow.contentContainer.hidden) {
                    floatingWindow.contentContainer.hidden = NO;
                    floatingWindow.contentContainer.alpha = 0;
                    [UIView animateWithDuration:0.25 animations:^{
                        floatingWindow.contentContainer.alpha = 1;
                    }];
                }
                
                [memoryVC jumpToAddress:record.instructionAddr];
                [memoryVC selectDataType:4];
                [self.view.window setHidden:YES];
            }
        };
        
        cell.onRegisterTapped = ^{
            SSRegisterPopupView *popupView = [SSRegisterPopupView sharedInstance];
            popupView.instructionAddress = record.instructionAddr;
            [popupView showInView:self.view];
        };
    }
    
    // 修改单元格背景视图
    UIView *bgView = [[UIView alloc] init];
    bgView.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:1.0];
    bgView.layer.cornerRadius = 8;
    cell.backgroundView = bgView;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 48.0;  // 增加行高以容纳两行文
}


- (void)dealloc {
    [LoggingService log:@"SSTrackPopViewController 被释放"];
}

- (void)show {
    self.view.hidden = NO;
    self.view.alpha = 0;
    
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 1;
    }];
}

+ (instancetype)sharedInstance {
    static SSTrackPopViewController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)clearInputButtonTapped {
    self.addressField.text = @"";
}

@end

@implementation SSCopyMenuView

- (instancetype)init {
    if (self = [super init]) {
        self.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:0.95];
        self.layer.cornerRadius = 12;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 12;
        self.layer.shadowOpacity = 0.3;
        
        // 修改按钮样式
        for (UIButton *button in self.subviews) {
            if ([button isKindOfClass:[UIButton class]]) {
                button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
                [button setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
                [button setBackgroundImage:[self imageWithColor:[UIColor colorWithWhite:1.0 alpha:0.1]] 
                                forState:UIControlStateHighlighted];
            }
        }
    }
    return self;
}

// 建纯色图片的辅助方法
- (UIImage *)imageWithColor:(UIColor *)color {
    CGRect rect = CGRectMake(0, 0, 1, 1);
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, rect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)copyInstructionTapped {
    if (self.onCopyInstruction) {
        self.onCopyInstruction();
    }
    [self dismiss];
}

- (void)viewInstructionTapped {
    if (self.onViewInstruction) {
        self.onViewInstruction();
    }
    [self dismiss];
}

- (void)showInView:(UIView *)view fromRect:(CGRect)rect {
    CGFloat menuWidth = 180; // 减小菜单宽度
    CGFloat menuHeight = 132; // 调整菜单高度
    
    // 计算理想的显示位置
    CGFloat idealX = rect.origin.x;
    CGFloat idealY = rect.origin.y + rect.size.height;
    
    // 确保菜单不会超出屏幕右边界
    if (idealX + menuWidth > view.bounds.size.width) {
        idealX = view.bounds.size.width - menuWidth - 10; // 右边留10点边距
    }
    
    // 确保菜单不会超出屏幕左边界
    if (idealX < 10) {
        idealX = 10; // 左边留10点边距
    }
    
    // 检下方是否有足够空间
    BOOL showBelow = (idealY + menuHeight <= view.bounds.size.height - 10);
    
    // 如果下方空间不足，就显示在上方
    if (!showBelow) {
        idealY = rect.origin.y - menuHeight;
    }
    
    self.frame = CGRectMake(idealX, idealY, menuWidth, menuHeight);
    [view addSubview:self];
    
    // 添加景遮罩
    UIView *bgView = [[UIView alloc] initWithFrame:view.bounds];
    bgView.backgroundColor = [UIColor clearColor];
    [bgView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)]];
    [view insertSubview:bgView belowSubview:self];
    objc_setAssociatedObject(self, "bgView", bgView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 动画显示
    self.alpha = 0;
    self.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    }];
}

- (void)dismiss {
    UIView *bgView = objc_getAssociatedObject(self, "bgView");
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [bgView removeFromSuperview];
        [self removeFromSuperview];
    }];
}

@end 