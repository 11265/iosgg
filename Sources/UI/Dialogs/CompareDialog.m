#import "UI/Dialogs/CompareDialog.h"
#import "Services/LogService.h"
#import "Services/Scanner/Scanner.h"
#import "UI/Dialogs/SearchDialog.h"

@interface SSComparePopViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *dataTypeContainer;
@property (nonatomic, strong) NSMutableArray<UIButton *> *typeButtons;
@property (nonatomic, assign) NSInteger selectedTypeIndex;
@property (nonatomic, strong) UITextField *valueTextField;
@property (nonatomic, strong) NSLayoutConstraint *contentCenterYConstraint;

@property (nonatomic, strong) UIButton *searchButton;

@end

@implementation SSComparePopViewController

+ (instancetype)comparePopViewController {
    return [[self alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self setupKeyboardNotifications];
}

- (void)setupUI {
    // 半透明背景
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    
    // 内容视图
    self.contentView = [[UIView alloc] init];
    self.contentView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    [self.view addSubview:self.contentView];
    
    // 设置内容视图约束
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentCenterYConstraint = [self.contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        self.contentCenterYConstraint,
        [self.contentView.widthAnchor constraintEqualToConstant:300],
        [self.contentView.heightAnchor constraintEqualToConstant:180]
    ]];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"对比搜索";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:titleLabel];
    
    // 创建数据类型选择容器
    self.dataTypeContainer = [[UIView alloc] init];
    self.dataTypeContainer.backgroundColor = [UIColor whiteColor];
    self.dataTypeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.dataTypeContainer];

    // 数据类型容器约束
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        
        [self.dataTypeContainer.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10],
        [self.dataTypeContainer.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.dataTypeContainer.widthAnchor constraintEqualToConstant:300],
        [self.dataTypeContainer.heightAnchor constraintEqualToConstant:30]
    ]];

    // 初始化按钮数组
    self.typeButtons = [NSMutableArray array];
    // 所有模式都显示所有类型
    NSArray *types = @[@"变化", @"不变", @"增加", @"减少", @"增加了", @"减少了"];
    CGFloat buttonWidth = 300.0f / types.count;

    // 创建类型按钮
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        [button setTitle:types[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
        button.titleLabel.font = [UIFont systemFontOfSize:14];
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

    // 默认选中第一个按钮
    [self typeButtonTapped:self.typeButtons.firstObject];
    
    // 添加数据类型标签，提示用户当前正在使用的数据类型
    UILabel *dataTypeLabel = [[UILabel alloc] init];
    NSString *typeStr = @"i32";
    switch (当前数据类型) {
        case SearchDataTypeU8: typeStr = @"i8"; break;
        case SearchDataTypeI16: typeStr = @"i16"; break;
        case SearchDataTypeI32: typeStr = @"i32"; break;
        case SearchDataTypeI64: typeStr = @"i64"; break;
        case SearchDataTypeF32: typeStr = @"f32"; break;
        case SearchDataTypeF64: typeStr = @"f64"; break;
        default: typeStr = @"i32"; break;
    }
    dataTypeLabel.text = [NSString stringWithFormat:@"当前数据类型: %@", typeStr];
    dataTypeLabel.font = [UIFont systemFontOfSize:12];
    dataTypeLabel.textColor = [UIColor whiteColor];
    dataTypeLabel.textAlignment = NSTextAlignmentRight;
    dataTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:dataTypeLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [dataTypeLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [dataTypeLabel.rightAnchor constraintEqualToAnchor:self.contentView.rightAnchor constant:-10]
    ]];
    
    // 添加搜索按钮
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [searchButton setTitle:@"搜索" forState:UIControlStateNormal];
    searchButton.backgroundColor = [UIColor systemBlueColor];
    [searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.contentView addSubview:searchButton];
    self.searchButton = searchButton; // 保存引用
    
    // 设置约束
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 在数据类型容器下方添加输入框
    UITextField *valueField = [[UITextField alloc] init];
    valueField.placeholder = @"请输入变化值";
    valueField.borderStyle = UITextBorderStyleNone;
    valueField.backgroundColor = [UIColor lightGrayColor];
    valueField.keyboardType = UIKeyboardTypeNumberPad;
    valueField.enabled = NO; // 默认禁用
    valueField.hidden = YES; // 默认隐藏
    valueField.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:valueField];
    self.valueTextField = valueField;
    
    // 设置输入框约束
    valueField.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        // 输入框约束
        [valueField.topAnchor constraintEqualToAnchor:self.dataTypeContainer.bottomAnchor constant:20],
        [valueField.leftAnchor constraintEqualToAnchor:self.contentView.leftAnchor],
        [valueField.rightAnchor constraintEqualToAnchor:self.contentView.rightAnchor],
        [valueField.heightAnchor constraintEqualToConstant:30],
        
        // 搜索按钮约束
        [searchButton.topAnchor constraintEqualToAnchor:valueField.bottomAnchor constant:20],
        [searchButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [searchButton.widthAnchor constraintEqualToConstant:120],
        [searchButton.heightAnchor constraintEqualToConstant:30]
    ]];
    
    [searchButton addTarget:self action:@selector(searchButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // 设置输入框代理
    valueField.delegate = self;
    [valueField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    
    // 初始化搜索按钮状态
    [self updateSearchButtonState];
}

- (void)textFieldDidChange:(UITextField *)textField {
    [self updateSearchButtonState];
}

- (void)updateSearchButtonState {
    BOOL shouldEnable = YES;
    
    // 增加了多少(4) 和 减少了多少(5) 需要输入值
    if (self.selectedTypeIndex == 4 || self.selectedTypeIndex == 5) {
        if (!self.valueTextField.text || self.valueTextField.text.length == 0) {
            shouldEnable = NO;
        }
    }
    
    self.searchButton.enabled = shouldEnable;
    self.searchButton.backgroundColor = shouldEnable ? [UIColor systemBlueColor] : [UIColor lightGrayColor];
}

- (void)closeButtonTapped {
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch.view == self.view) {
        [self.view endEditing:YES];
        [self closeButtonTapped];
    }
}

- (void)searchButtonTapped {
    [LoggingService log:@"开始执行对比搜索"];
    
    数值 searchValue = {0};
    数据类型 dataType;
    对比类型 compType;
    
    // 使用当前全局数据类型
    switch (当前数据类型) {
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
    
    // 根据选中的类型设置对比类型
    switch (self.selectedTypeIndex) {
        case 0:
            compType = 变化;
            break;
        case 1:
            compType = 不变;
            break;
        case 2:
            compType = 增加了;
            break;
        case 3:
            compType = 减少了;
            break;
        case 4:
            compType = 增加了多少;
            // 根据数据类型设置正确的值
            switch (dataType) {
                case 类型_字节:
                    searchValue.b = [self.valueTextField.text intValue] & 0xFF;
                    break;
                case 类型_短整数:
                    searchValue.s = [self.valueTextField.text intValue] & 0xFFFF;
                    break;
                case 类型_整数:
                    searchValue.i = [self.valueTextField.text intValue];
                    break;
                case 类型_长整数:
                    searchValue.l = [self.valueTextField.text longLongValue];
                    break;
                case 类型_浮点:
                    searchValue.f = [self.valueTextField.text floatValue];
                    break;
                case 类型_双精度:
                    searchValue.d = [self.valueTextField.text doubleValue];
                    break;
                default:
                    break;
            }
            break;
        case 5:
            compType = 减少了多少;
            // 根据数据类型设置正确的值
            switch (dataType) {
                case 类型_字节:
                    searchValue.b = [self.valueTextField.text intValue] & 0xFF;
                    break;
                case 类型_短整数:
                    searchValue.s = [self.valueTextField.text intValue] & 0xFFFF;
                    break;
                case 类型_整数:
                    searchValue.i = [self.valueTextField.text intValue];
                    break;
                case 类型_长整数:
                    searchValue.l = [self.valueTextField.text longLongValue];
                    break;
                case 类型_浮点:
                    searchValue.f = [self.valueTextField.text floatValue];
                    break;
                case 类型_双精度:
                    searchValue.d = [self.valueTextField.text doubleValue];
                    break;
                default:
                    break;
            }
            break;
        default:
            compType = 变化;
            break;
    }
    
    [LoggingService log:@"执行搜索 - 模式: %d, 类型: %d, 数据类型: %d", 当前搜索模式, compType, dataType];
    
    // 根据当前搜索模式执行对应的搜索
    if (当前搜索模式 == 模式二) {
        搜索模式二(searchValue, dataType, compType);
    }
    
    // 关闭弹窗
    [self closeButtonTapped];
}

- (void)typeButtonTapped:(UIButton *)sender {
    // 更新所有按钮状态
    for (UIButton *button in self.typeButtons) {
        button.selected = (button == sender);
        button.backgroundColor = button.selected ? 
            [UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0] : 
            [UIColor whiteColor];
    }
    self.selectedTypeIndex = sender.tag;
    
    // 对于"增加了多少"和"减少了多少"类型显示输入框
    BOOL shouldShowTextField = (sender.tag == 4 || sender.tag == 5);
    self.valueTextField.hidden = !shouldShowTextField;
    self.valueTextField.enabled = shouldShowTextField;
    self.valueTextField.backgroundColor = shouldShowTextField ? [UIColor whiteColor] : [UIColor lightGrayColor];
    
    // 更新提示词
    if (sender.tag == 4) {
        self.valueTextField.placeholder = @"请输入增加了多少";
    } else if (sender.tag == 5) {
        self.valueTextField.placeholder = @"请输入减少了多少";
    }
    
    // 更新搜索按钮状态
    [self updateSearchButtonState];
    
    [self.view layoutIfNeeded];
}

// 添加键盘通知观察
- (void)setupKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillShow:)
                                               name:UIKeyboardWillShowNotification
                                             object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification
                                             object:nil];
}

// 处理键盘显示
- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = keyboardFrame.size.height;
    
    // 计算内容视图底部到屏幕底部的距离
    CGRect contentFrameInWindow = [self.contentView convertRect:self.contentView.bounds toView:nil];
    CGFloat bottomSpace = CGRectGetMaxY(contentFrameInWindow);
    CGFloat screenHeight = UIScreen.mainScreen.bounds.size.height;
    CGFloat overlap = bottomSpace - (screenHeight - keyboardHeight);
    
    // 如果有重叠，向上移动内容视图
    if (overlap > 0) {
        self.contentCenterYConstraint.constant = -overlap - 20; // 额外20点的间距
        
        // 使用与键盘相同的动画参数
        NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        UIViewAnimationCurve curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
        
        [UIView animateWithDuration:duration
                              delay:0
                            options:(curve << 16)
                         animations:^{
            [self.view layoutIfNeeded];
        } completion:nil];
    }
}

// 处理键盘隐藏
- (void)keyboardWillHide:(NSNotification *)notification {
    self.contentCenterYConstraint.constant = 0;
    
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    
    [UIView animateWithDuration:duration
                          delay:0
                        options:(curve << 16)
                     animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

// 实现UITextFieldDelegate方法，点击return收起键盘
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

// 清理通知观察者
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end 