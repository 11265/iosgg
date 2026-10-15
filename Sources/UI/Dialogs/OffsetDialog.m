#import "UI/Dialogs/OffsetDialog.h"
#import "Services/LogService.h"

// 定义通知常量
NSString * const kOffsetAppliedNotification = @"kOffsetAppliedNotification";

@interface SSOffsetPopViewController ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextField *offsetTextField;
@property (nonatomic, strong) UIButton *radioButton;
@property (nonatomic, strong) NSLayoutConstraint *contentCenterYConstraint;  // 添加约束属性

@end

@implementation SSOffsetPopViewController

+ (instancetype)offsetPopViewController {
    return [[SSOffsetPopViewController alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 设置背景半透明
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    
    // 创建容器视图
    self.contentView = [[UIView alloc] init];
    self.contentView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    [self.view addSubview:self.contentView];
    
    // 设置内容视图约束
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentCenterYConstraint = [self.contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        self.contentCenterYConstraint,  // 使用约束属性
        [self.contentView.widthAnchor constraintEqualToConstant:250],
        [self.contentView.heightAnchor constraintEqualToConstant:170]
    ]];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"地址偏移";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:titleLabel];
    
    // 创建偏移输入框
    self.offsetTextField = [[UITextField alloc] init];
    self.offsetTextField.placeholder = @"请输入偏移值";
    self.offsetTextField.backgroundColor = [UIColor whiteColor];
    self.offsetTextField.borderStyle = UITextBorderStyleNone;
    self.offsetTextField.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.offsetTextField];
    
    // 添加HEX标签
    UILabel *hexLabel = [[UILabel alloc] init];
    hexLabel.text = @"HEX";
    hexLabel.font = [UIFont systemFontOfSize:14];
    hexLabel.textColor = [UIColor whiteColor];
    [self.contentView addSubview:hexLabel];
    
    // 添加圆形单选框
    self.radioButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.radioButton.layer.cornerRadius = 10;
    self.radioButton.layer.borderWidth = 2;
    self.radioButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.radioButton.backgroundColor = [UIColor clearColor];
    [self.radioButton addTarget:self action:@selector(radioButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.radioButton];
    
    // 添加确定按钮
    UIButton *confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [confirmButton setTitle:@"确定" forState:UIControlStateNormal];
    confirmButton.backgroundColor = [UIColor systemBlueColor];
    [confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [confirmButton addTarget:self action:@selector(confirmButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:confirmButton];
    
    // 设置约束
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.offsetTextField.translatesAutoresizingMaskIntoConstraints = NO;
    confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    hexLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.radioButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 标题约束
        [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:15],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        
        // 偏移输入框约束
        [self.offsetTextField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [self.offsetTextField.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor constant:20],
        [self.offsetTextField.widthAnchor constraintEqualToConstant:140],
        [self.offsetTextField.heightAnchor constraintEqualToConstant:30],
        
        // HEX标签约束
        [hexLabel.centerYAnchor constraintEqualToAnchor:self.offsetTextField.centerYAnchor],
        [hexLabel.trailingAnchor constraintEqualToAnchor:self.radioButton.leadingAnchor constant:-5],
        
        // 单选框约束
        [self.radioButton.centerYAnchor constraintEqualToAnchor:self.offsetTextField.centerYAnchor],
        [self.radioButton.trailingAnchor constraintEqualToAnchor:self.offsetTextField.leadingAnchor constant:-10],
        [self.radioButton.widthAnchor constraintEqualToConstant:20],
        [self.radioButton.heightAnchor constraintEqualToConstant:20],
        
        // 确定按钮约束
        [confirmButton.topAnchor constraintEqualToAnchor:self.offsetTextField.bottomAnchor constant:20],
        [confirmButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [confirmButton.widthAnchor constraintEqualToConstant:120],
        [confirmButton.heightAnchor constraintEqualToConstant:35]
    ]];
    
    // 添加点击背景关闭的手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
    [self.view addGestureRecognizer:tapGesture];
    
    // 添加键盘通知监听
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

// 点击空白处收起键盘
- (void)backgroundTapped:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    if (!CGRectContainsPoint(self.contentView.frame, location)) {
        [self.offsetTextField resignFirstResponder];  // 收起键盘
        [UIView animateWithDuration:0.25 animations:^{
            self.view.alpha = 0;
        } completion:^(BOOL finished) {
            [self.view removeFromSuperview];
            [self removeFromParentViewController];
        }];
    }
}

// 实现 UITextFieldDelegate
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];  // 点击回车收起键盘
    return YES;
}

// 在 dealloc 中移除通知监听
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)confirmButtonTapped:(UIButton *)sender {
    // 获取输入的偏移值
    NSString *offsetText = self.offsetTextField.text;
    
    // 检查输入是否为空
    if (offsetText.length == 0) {
        [LoggingService log:@"偏移值不能为空"];
        return;
    }
    
    // 去除空白字符
    offsetText = [offsetText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (offsetText.length == 0) {
        [LoggingService log:@"偏移值不能为空"];
        return;
    }
    
    BOOL isHex = self.radioButton.selected;
    
    // 解析偏移值
    int64_t offset = 0;
    BOOL validInput = NO;
    
    if (isHex) {
        // 十六进制解析
        NSString *hexString = offsetText;
        // 如果没有0x前缀，自动添加
        if (![hexString hasPrefix:@"0x"]) {
            hexString = [@"0x" stringByAppendingString:hexString];
        }
        NSScanner *scanner = [NSScanner scannerWithString:hexString];
        unsigned long long tempOffset;
        if ([scanner scanHexLongLong:&tempOffset] && scanner.isAtEnd) {
            offset = (int64_t)tempOffset;
            validInput = YES;
        }
    } else {
        // 十进制解析
        // 如果有0x前缀，移除它
        if ([offsetText hasPrefix:@"0x"]) {
            offsetText = [offsetText substringFromIndex:2];
        }
        NSScanner *scanner = [NSScanner scannerWithString:offsetText];
        long long tempOffset;
        if ([scanner scanLongLong:&tempOffset] && scanner.isAtEnd) {
            offset = tempOffset;
            validInput = YES;
        }
    }
    
    if (!validInput) {
        [LoggingService log:@"无效的偏移值: %@", offsetText];
        return;
    }
    
    [LoggingService log:@"应用偏移值: %lld (Hex: %@)", offset, isHex ? @"YES" : @"NO"];
    
    // 发送通知，包含偏移值
    [[NSNotificationCenter defaultCenter] postNotificationName:kOffsetAppliedNotification
                                                      object:nil
                                                    userInfo:@{@"offset": @(offset)}];
    
    // 关闭弹窗
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    }];
}

- (void)radioButtonTapped:(UIButton *)sender {
    sender.selected = !sender.selected;
    if (sender.selected) {
        sender.backgroundColor = [UIColor whiteColor];
        // 如果当前有输入值，自动添加0x前缀
        if (self.offsetTextField.text.length > 0 && ![self.offsetTextField.text hasPrefix:@"0x"]) {
            self.offsetTextField.text = [@"0x" stringByAppendingString:self.offsetTextField.text];
        }
    } else {
        sender.backgroundColor = [UIColor clearColor];
        // 如果当前值有0x前缀，移除它
        if ([self.offsetTextField.text hasPrefix:@"0x"]) {
            self.offsetTextField.text = [self.offsetTextField.text substringFromIndex:2];
        }
    }
}

@end 