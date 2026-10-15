#import "UI/Dialogs/SignatureDialog.h"
#import "Services/Scanner/SignatureScanner.h"
#import "Services/LogService.h"
#import "UI/Pages/SearchPage.h"

// 添加搜索回调函数
static void searchResultCallback(uint64_t* results, size_t count) {
    [LoggingService log:@"特征码搜索回调被触发 - 结果数量: %zu", count];
    
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
    
    // 在主线程更新UI
    dispatch_async(dispatch_get_main_queue(), ^{
        [searchVC updateSearchResults:addresses withType:SearchDataTypeI32];
    });
}

@interface SSSignaturePopViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, strong) NSLayoutConstraint *contentCenterYConstraint;

@end

@implementation SSSignaturePopViewController

+ (instancetype)signaturePopViewController {
    return [[SSSignaturePopViewController alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 设置特征码搜索回调
    设置特征码搜索回调(searchResultCallback);
    
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
        self.contentCenterYConstraint,
        [self.contentView.widthAnchor constraintEqualToConstant:250],
        [self.contentView.heightAnchor constraintEqualToConstant:150]
    ]];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"特征码搜索";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:titleLabel];
    
    // 创建搜索输入框
    self.searchTextField = [[UITextField alloc] init];
    self.searchTextField.placeholder = @"请输入特征码";
    self.searchTextField.backgroundColor = [UIColor whiteColor];
    self.searchTextField.borderStyle = UITextBorderStyleNone;
    self.searchTextField.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.searchTextField];
    
    // 添加搜索按钮
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [searchButton setTitle:@"搜索" forState:UIControlStateNormal];
    searchButton.backgroundColor = [UIColor systemBlueColor];
    [searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [searchButton addTarget:self action:@selector(searchButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:searchButton];
    
    // 设置约束
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchTextField.translatesAutoresizingMaskIntoConstraints = NO;
    searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 标题约束
        [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:15],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        
        // 搜索输入框约束
        [self.searchTextField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [self.searchTextField.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.searchTextField.widthAnchor constraintEqualToConstant:250],
        [self.searchTextField.heightAnchor constraintEqualToConstant:30],
        
        // 搜索按钮约束
        [searchButton.topAnchor constraintEqualToAnchor:self.searchTextField.bottomAnchor constant:20],
        [searchButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [searchButton.widthAnchor constraintEqualToConstant:120],
        [searchButton.heightAnchor constraintEqualToConstant:40]
    ]];
    
    // 添加点击背景关闭的手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
    [self.view addGestureRecognizer:tapGesture];
    
    // 设置输入框代理
    self.searchTextField.delegate = self;
    
    // 添加键盘通知观察
    [self setupKeyboardNotifications];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    if (!CGRectContainsPoint(self.contentView.frame, location)) {
        [UIView animateWithDuration:0.25 animations:^{
            self.view.alpha = 0;
        } completion:^(BOOL finished) {
            [self.view removeFromSuperview];
            [self removeFromParentViewController];
        }];
    }
}

- (void)searchButtonTapped:(UIButton *)sender {
    NSString *signatureCode = self.searchTextField.text;
    if (!signatureCode || signatureCode.length == 0) {
        [LoggingService log:@"错误：请输入特征码"];
        return;
    }
    
    [LoggingService log:@"开始特征码搜索: %@", signatureCode];
    
    // 将NSString转换为C字符串
    const char *pattern = [signatureCode UTF8String];
    
    // 调用搜索模式三
    搜索模式三(pattern);
    
    // 关闭弹窗
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    }];
}

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

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end 