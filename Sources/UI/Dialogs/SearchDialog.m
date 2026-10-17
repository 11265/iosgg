#import "UI/Dialogs/SearchDialog.h"
#import <objc/runtime.h>
#import "Modules/Scanner/Scanner.h"
#import "Services/LogService.h"
#import "UI/Pages/Scanner/SearchPage.h"

// 定义搜索模式枚举
typedef NS_ENUM(NSInteger, SearchMode) {
    SearchModeNone = 0,    // 未搜索
    SearchModeOne,         // 模式一
    SearchModeTwo          // 模式二
};

@interface SSSearchPopViewController () <UICollectionViewDelegate, UICollectionViewDataSource>

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, strong) UIView *leftContainerView;    // 左侧容器
@property (nonatomic, strong) UICollectionView *buttonCollectionView;
@property (nonatomic, copy) NSArray *buttonTitles;
@property (nonatomic, strong) UIView *dataTypeContainer;  // 替换 dataTypeSegment
@property (nonatomic, strong) NSMutableArray<UIButton *> *typeButtons;
@property (nonatomic, assign) NSInteger selectedTypeIndex;
@property (nonatomic, assign) BOOL isFirstSearch; // 是否是第一次搜索
@property (nonatomic, assign) CGRect originalContainerFrame; // 添加属性记录原始位置
@property (nonatomic, strong) NSLayoutConstraint *centerYConstraint; // 用于键盘避让

@end

@implementation SSSearchPopViewController

static void searchResultCallback(uint64_t* results, size_t count, size_t totalCount, SearchDataType type) {
    [LoggingService log:@"搜索回调被触发 - 回传: %zu / 命中: %zu, 类型: %d", count, totalCount, type];
    
    // 获取当前的 SearchPage 实例
    SearchPage *searchVC = [FloatingWindow sharedInstance].searchViewController;
    if (!searchVC) {
        [LoggingService log:@"错误：无法获取搜索视图控制器实例"];
        return;
    }
    
    // 将结果转换为 NSArray
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        [addresses addObject:@(results[i])];
    }
    
    // 直接调用更新方法，传递数据类型
    dispatch_async(dispatch_get_main_queue(), ^{
        [searchVC updateSearchResults:addresses totalCount:totalCount withType:type];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 添加点击手势识别器
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
    [self.view addGestureRecognizer:tapGesture];
    
    // 设置背景半透明
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    
    // 创建容器视图
    self.containerView = [[UIView alloc] init];
    self.containerView.backgroundColor = [UIColor colorWithRed:240/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];  // 浅灰色背景
    self.containerView.layer.cornerRadius = 10;
    [self.view addSubview:self.containerView];
    
    // 设置容器视图约束
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.centerYConstraint = [self.containerView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        self.centerYConstraint,
        [self.containerView.widthAnchor constraintEqualToConstant:220],
        [self.containerView.heightAnchor constraintEqualToConstant:160]  // 减小容器高度
    ]];
    
    // 首先创建左侧容器
    self.leftContainerView = [[UIView alloc] init];
    self.leftContainerView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    [self.containerView addSubview:self.leftContainerView];
    self.leftContainerView.translatesAutoresizingMaskIntoConstraints = NO;

    // 设置左侧容器填充整个主容器
    [NSLayoutConstraint activateConstraints:@[
        [self.leftContainerView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [self.leftContainerView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [self.leftContainerView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [self.leftContainerView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor]
    ]];
    
    // 然后创建标签
    UILabel *searchLabel = [[UILabel alloc] init];
    searchLabel.text = @"精确搜索";
    searchLabel.textColor = [UIColor whiteColor];
    searchLabel.font = [UIFont systemFontOfSize:14];
    searchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leftContainerView addSubview:searchLabel];
    
    // 设置标签约束
    [NSLayoutConstraint activateConstraints:@[
        [searchLabel.topAnchor constraintEqualToAnchor:self.leftContainerView.topAnchor constant:10],
        [searchLabel.centerXAnchor constraintEqualToAnchor:self.leftContainerView.centerXAnchor],
    ]];
    
    // 先创建数据类型选择容器
    self.dataTypeContainer = [[UIView alloc] init];
    self.dataTypeContainer.backgroundColor = [UIColor whiteColor];
    self.dataTypeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leftContainerView addSubview:self.dataTypeContainer];

    // 设置数据类型容器约束 - 现在是在标签下方
    [NSLayoutConstraint activateConstraints:@[
        [self.dataTypeContainer.topAnchor constraintEqualToAnchor:searchLabel.bottomAnchor constant:10],
        [self.dataTypeContainer.leadingAnchor constraintEqualToAnchor:self.leftContainerView.leadingAnchor],
        [self.dataTypeContainer.trailingAnchor constraintEqualToAnchor:self.leftContainerView.trailingAnchor],
        [self.dataTypeContainer.heightAnchor constraintEqualToConstant:30]
    ]];

    // 初始化按钮数组
    self.typeButtons = [NSMutableArray array];
    NSArray *types = @[@"i8", @"i16", @"i32", @"i64", @"f32", @"f64"];

    // 计算实际可用宽度（容器宽度为220.0f）
    CGFloat containerWidth = 220.0f;
    CGFloat buttonWidth = containerWidth / types.count;  // 平均分配宽度

    // 创建类型按钮
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        [button setTitle:types[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
        button.titleLabel.font = [UIFont systemFontOfSize:12]; // 稍微调小字体以适应更多按钮
        button.backgroundColor = [UIColor whiteColor];
        [button addTarget:self action:@selector(typeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        button.frame = CGRectMake(buttonWidth * i, 0, buttonWidth, 30);
        [self.dataTypeContainer addSubview:button];
        [self.typeButtons addObject:button];
        
        // 添加右边框（除了最后一个按钮）
        if (i < types.count - 1) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(buttonWidth * (i + 1), 0, 1, 30)];
            separator.backgroundColor = [UIColor colorWithRed:200/255.0 green:200/255.0 blue:200/255.0 alpha:1.0];
            [self.dataTypeContainer addSubview:separator];
        }
    }

    // 根据当前数据类型选择对应的按钮，但不触发类型切换
    NSInteger buttonIndex = 0;
    switch (当前数据类型) {
        case SearchDataTypeU8:
            buttonIndex = 0;
            break;
        case SearchDataTypeI16:
            buttonIndex = 1;
            break;
        case SearchDataTypeI32:
            buttonIndex = 2;
            break;
        case SearchDataTypeI64:
            buttonIndex = 3;
            break;
        case SearchDataTypeF32:
            buttonIndex = 4;
            break;
        case SearchDataTypeF64:
            buttonIndex = 5;
            break;
        default:
            buttonIndex = 2; // 默认 i32
            break;
    }
    
    // 只更新按钮状态，不改变当前数据类型
    UIButton *selectedButton = self.typeButtons[buttonIndex];
    for (UIButton *button in self.typeButtons) {
        button.selected = (button == selectedButton);
        button.backgroundColor = button.selected ? 
            [UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0] : 
            [UIColor whiteColor];
    }
    self.selectedTypeIndex = buttonIndex;
    
    // 然后创建搜索框
    self.searchTextField = [[UITextField alloc] init];
    self.searchTextField.placeholder = @"请输入搜索内容";
    self.searchTextField.borderStyle = UITextBorderStyleNone;
    self.searchTextField.backgroundColor = [UIColor whiteColor];
    self.searchTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.searchTextField.textAlignment = NSTextAlignmentCenter;
    
    [self.leftContainerView addSubview:self.searchTextField];
    
    // 设置搜索框约束 - 现在是在类型选择器下方
    [NSLayoutConstraint activateConstraints:@[
        [self.searchTextField.topAnchor constraintEqualToAnchor:self.dataTypeContainer.bottomAnchor constant:10],
        [self.searchTextField.leadingAnchor constraintEqualToAnchor:self.leftContainerView.leadingAnchor],
        [self.searchTextField.trailingAnchor constraintEqualToAnchor:self.leftContainerView.trailingAnchor],
        [self.searchTextField.heightAnchor constraintEqualToConstant:30]
    ]];
    
    // 修改按钮标题数组为20个按钮
    self.buttonTitles = @[
        @"7", @"8", @"9", @"A", @"D",
        @"4", @"5", @"6", @"B", @"E",
        @"1", @"2", @"3", @"C", @"F",
        @"0x", @"0", @".", @"删除", @"清空"
    ];
    
    // 创建重置按钮
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resetButton setTitle:@"重置" forState:UIControlStateNormal];
    [resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetButton.backgroundColor = [UIColor systemGrayColor];
    [resetButton addTarget:self action:@selector(resetButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftContainerView addSubview:resetButton];
    
    // 创建搜索按钮
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [searchButton setTitle:@"搜索" forState:UIControlStateNormal];
    [searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    searchButton.backgroundColor = [UIColor systemBlueColor];
    [searchButton addTarget:self action:@selector(searchButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftContainerView addSubview:searchButton];

    // 设置两个按钮的约束
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    searchButton.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        // 重置按钮约束
        [resetButton.topAnchor constraintEqualToAnchor:self.searchTextField.bottomAnchor constant:10],
        [resetButton.trailingAnchor constraintEqualToAnchor:self.leftContainerView.centerXAnchor constant:-5],
        [resetButton.widthAnchor constraintEqualToConstant:80],
        [resetButton.heightAnchor constraintEqualToConstant:35],
        
        // 搜索按钮约束
        [searchButton.topAnchor constraintEqualToAnchor:self.searchTextField.bottomAnchor constant:10],
        [searchButton.leadingAnchor constraintEqualToAnchor:self.leftContainerView.centerXAnchor constant:5],
        [searchButton.widthAnchor constraintEqualToConstant:80],
        [searchButton.heightAnchor constraintEqualToConstant:35]
    ]];
    
    // 初始化搜索状态
    self.isFirstSearch = YES;
    
    // 使用 RETAIN 策略存储当前实例
    objc_setAssociatedObject([UIApplication sharedApplication], 
                           "CurrentSearchPopViewController", 
                           self, 
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 设置搜索回调
    设置搜索回调(searchResultCallback);
    
    [LoggingService log:@"搜索弹窗已初始化，当前数据类型: %d", 当前数据类型];
    
    // 添加键盘通知观察
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillShow:)
                                               name:UIKeyboardWillShowNotification
                                             object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification
                                             object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    
    // 如果点击在容器视图外部
    if (!CGRectContainsPoint(self.containerView.frame, location)) {
        // 关闭弹窗
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    } else {
        // 如果点击在容器内但不在输入框上，收起键盘
        CGPoint locationInContainer = [gesture locationInView:self.containerView];
        CGRect textFieldFrame = [self.searchTextField.superview convertRect:self.searchTextField.frame toView:self.containerView];
        
        if (!CGRectContainsPoint(textFieldFrame, locationInContainer)) {
            [self.searchTextField resignFirstResponder];
        }
    }
}

+ (instancetype)searchPopViewController {
    SSSearchPopViewController *vc = [[SSSearchPopViewController alloc] init];
    return vc;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.buttonTitles.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ButtonCell" forIndexPath:indexPath];
    
    // 移除之前按钮（如果存在）
    [[cell.contentView viewWithTag:100] removeFromSuperview];
    
    // 创建按钮
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = 100;
    [button setTitle:self.buttonTitles[indexPath.item] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    button.titleLabel.font = [UIFont systemFontOfSize:18];
    [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // 添加按下效果
    [button addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(buttonTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];
    
    button.frame = cell.contentView.bounds;
    [cell.contentView addSubview:button];
    
    return cell;
}

#pragma mark - Button Action

- (void)buttonTouchDown:(UIButton *)sender {
    sender.backgroundColor = [UIColor colorWithRed:255/255.0 green:115/255.0 blue:0/255.0 alpha:1.0];
}

- (void)buttonTouchUpOutside:(UIButton *)sender {
    // 延迟0.1秒后恢复颜色
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sender.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    });
}

- (void)buttonTapped:(UIButton *)sender {
    // 延迟0.1秒后恢复颜色
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sender.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    });
    
    NSString *buttonTitle = [sender titleForState:UIControlStateNormal];
    
    // 如果是清空按钮，则清空输入框内容
    if ([buttonTitle isEqualToString:@"清空"]) {
        self.searchTextField.text = @"";
        return;
    }
    
    // 如果是删除按钮，则删除最后一个字符
    if ([buttonTitle isEqualToString:@"删除"]) {
        NSString *currentText = self.searchTextField.text ?: @"";
        if (currentText.length > 0) {
            self.searchTextField.text = [currentText substringToIndex:currentText.length - 1];
        }
        return;
    }
    
    // 如果是粘贴按钮，则粘贴剪贴板内容
    if ([buttonTitle isEqualToString:@"粘贴"]) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSString *pasteboardString = pasteboard.string;
        if (pasteboardString) {
            NSString *currentText = self.searchTextField.text ?: @"";
            self.searchTextField.text = [currentText stringByAppendingString:pasteboardString];
        }
        return;
    }
    
    // 其他按钮原有逻辑
    NSString *currentText = self.searchTextField.text ?: @"";
    self.searchTextField.text = [currentText stringByAppendingString:buttonTitle];
}

- (void)searchButtonTapped:(UIButton *)sender {
    NSString *searchText = self.searchTextField.text;
    if (!searchText || searchText.length == 0) {
        [LoggingService log:@"错误：请输入搜索值"];
        return;
    }
    [LoggingService log:@"获取搜索值: %@", searchText];
    
    // 创建搜索目标值
    数值 searchValue = {0};
    数据类型 dataType;
    
    // 获取当前的数据类型
    switch (当前数据类型) {
        case SearchDataTypeU8:
            dataType = 类型_字节;
            break;
        case SearchDataTypeI16:
            dataType = 类型_短整数;
            break;
        case SearchDataTypeI32:
            dataType = 类型_整数;
            break;
        case SearchDataTypeI64:
            dataType = 类型_长整数;
            break;
        case SearchDataTypeF32:
            dataType = 类型_浮点;
            break;
        case SearchDataTypeF64:
            dataType = 类型_双精度;
            break;
        default:
            dataType = 类型_整数;
            break;
    }
    
    // 检查是否为区间搜索格式
    NSString *normalizedText = [searchText stringByReplacingOccurrencesOfString:@"～" withString:@"~"];
    NSArray *rangeComponents = [normalizedText componentsSeparatedByString:@"~"];
    if (rangeComponents.count == 2) {
        // 根据数据类型解析区间值
        switch (dataType) {
            case 类型_整数:
                searchValue.range_i.min = [[rangeComponents objectAtIndex:0] intValue];
                searchValue.range_i.max = [[rangeComponents objectAtIndex:1] intValue];
                [LoggingService log:@"解析为区间搜索: %d 到 %d", searchValue.range_i.min, searchValue.range_i.max];
                break;
            case 类型_长整数:
                searchValue.range_l.min = [[rangeComponents objectAtIndex:0] longLongValue];
                searchValue.range_l.max = [[rangeComponents objectAtIndex:1] longLongValue];
                break;
            case 类型_浮点:
                searchValue.range_f.min = [[rangeComponents objectAtIndex:0] floatValue];
                searchValue.range_f.max = [[rangeComponents objectAtIndex:1] floatValue];
                break;
            case 类型_双精度:
                searchValue.range_d.min = [[rangeComponents objectAtIndex:0] doubleValue];
                searchValue.range_d.max = [[rangeComponents objectAtIndex:1] doubleValue];
                break;
            case 类型_字节:
                searchValue.range_i.min = [[rangeComponents objectAtIndex:0] intValue] & 0xFF;
                searchValue.range_i.max = [[rangeComponents objectAtIndex:1] intValue] & 0xFF;
                break;
            case 类型_短整数:
                searchValue.range_i.min = [[rangeComponents objectAtIndex:0] intValue] & 0xFFFF;
                searchValue.range_i.max = [[rangeComponents objectAtIndex:1] intValue] & 0xFFFF;
                break;
        }
        
        // 根据当前搜索模式执行搜索
        if (当前搜索模式 == 未搜索 || 当前搜索模式 == 模式二) {
            搜索模式二(searchValue, dataType, 区间);
        }
        
    } else {
        // 普通搜索的处理
        switch (dataType) {
            case 类型_整数:
                searchValue.i = [searchText intValue];
                break;
            case 类型_长整数:
                searchValue.l = [searchText longLongValue];
                break;
            case 类型_浮点:
                searchValue.f = [searchText floatValue];
                break;
            case 类型_双精度:
                searchValue.d = [searchText doubleValue];
                break;
            case 类型_字节:
                searchValue.b = [searchText intValue] & 0xFF;
                break;
            case 类型_短整数:
                searchValue.s = [searchText intValue] & 0xFFFF;
                break;
        }
        
        // 根据当前搜索模式执行搜索
        if (当前搜索模式 == 未搜索 || 当前搜索模式 == 模式二) {
            搜索模式二(searchValue, dataType, 精确);
        }
    }
    
    // 移除弹窗
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)resetButtonTapped:(UIButton *)sender {
    [LoggingService log:@"重置搜索状态"];
    self.isFirstSearch = YES;
    清理搜索();
    
    // 发送重置通知
    [[NSNotificationCenter defaultCenter] postNotificationName:kResetSearchNotification 
                                                      object:nil];
}

- (void)clearButtonTapped:(UIButton *)sender {
    // 查找并触发右侧容器中的"清"按钮
    for (UICollectionViewCell *cell in self.buttonCollectionView.visibleCells) {
        UIButton *button = [cell.contentView viewWithTag:100];
        if ([[button titleForState:UIControlStateNormal] isEqualToString:@"清空"]) {
            [self buttonTapped:button];
            break;
        }
    }
}

// 添加销方法
- (void)dealloc {
    // 移除键盘通知观察
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // 移除关联象
    objc_setAssociatedObject([UIApplication sharedApplication], 
                           "CurrentSearchPopViewController", 
                           nil, 
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    UIWindow *alertWindow = objc_getAssociatedObject(self, "alertWindow");
    alertWindow.hidden = YES;
}

- (void)typeButtonTapped:(UIButton *)sender {
    // 如果已经开始搜索，不允许切换数据类型
    if (当前搜索模式 != 未搜索) {
        [LoggingService log:@"搜索过程中无法切换数据类型"];
        return;
    }
    
    // 更新所有按钮状态
    for (UIButton *button in self.typeButtons) {
        button.selected = (button == sender);
        button.backgroundColor = button.selected ? 
            [UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0] : 
            [UIColor whiteColor];
    }
    self.selectedTypeIndex = sender.tag;
    
    // 根据选择的类型设置当前数据类型
    switch (sender.tag) {
        case 0:  // i8
            [ScannerState shared].currentDataType = SearchDataTypeU8;
            break;
        case 1:  // i16
            [ScannerState shared].currentDataType = SearchDataTypeI16;
            break;
        case 2:  // i32
            [ScannerState shared].currentDataType = SearchDataTypeI32;
            break;
        case 3:  // i64
            [ScannerState shared].currentDataType = SearchDataTypeI64;
            break;
        case 4:  // f32
            [ScannerState shared].currentDataType = SearchDataTypeF32;
            break;
        case 5:  // f64
            [ScannerState shared].currentDataType = SearchDataTypeF64;
            break;
        default:
            [ScannerState shared].currentDataType = SearchDataTypeI32;
            break;
    }
    
    [LoggingService log:@"数据类型已更新为: %d", 当前数据类型];
}

// 添加键盘显示处理方法
- (void)keyboardWillShow:(NSNotification *)notification {
    // 获取键盘信息
    NSDictionary *info = [notification userInfo];
    CGSize keyboardSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat keyboardHeight = keyboardSize.height;
    
    // 强制布局更新以获取准确坐标
    [self.view layoutIfNeeded];
    
    // 获取输入框在视图中的位置
    CGRect textFieldRect = [self.searchTextField convertRect:self.searchTextField.bounds toView:self.view];
    CGFloat textFieldBottom = CGRectGetMaxY(textFieldRect);
    
    // 获取视图高度
    CGFloat viewHeight = self.view.bounds.size.height;
    
    // 计算键盘顶部位置
    CGFloat keyboardTop = viewHeight - keyboardHeight;
    
    // 计算遮挡高度
    CGFloat overlap = textFieldBottom - keyboardTop;
    
    // 如果输入框被键盘遮挡，向上移动视图
    if (overlap > 0) {
        // 更新约束
        self.centerYConstraint.constant = -(overlap + 20); // 额外上移20点
        
        // 使用动画更新布局
        [UIView animateWithDuration:0.3 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
}

// 添加键盘隐藏处理方法
- (void)keyboardWillHide:(NSNotification *)notification {
    // 恢复约束
    self.centerYConstraint.constant = 0;
    
    [UIView animateWithDuration:0.3 animations:^{
        [self.view layoutIfNeeded];
    }];
}

@end 