#import "UI/Dialogs/GetSignatureDialog.h"

@interface SSPatternLengthView ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *inputTextField;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, assign) CGRect originalContainerFrame;  // 添加属性记录原始位置

@end

@implementation SSPatternLengthView

- (instancetype)initWithAddress:(uint64_t)address instruction:(uint32_t)instruction disassembly:(NSString *)disassembly {
    if (self = [super init]) {
        self.address = address;
        self.instruction = instruction;
        self.disassembly = disassembly;
        self.frame = [UIScreen mainScreen].bounds;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
        
        // 创建内容视图
        self.contentView = [[UIView alloc] init];
        self.contentView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
        [self addSubview:self.contentView];
        
        // 添加键盘通知观察
        [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
        
        self.originalContainerFrame = CGRectNull; // 初始化为 null
        
        // 标题标签
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.text = @"生成特征码长度";
        self.titleLabel.font = [UIFont systemFontOfSize:14];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.titleLabel];
        
        // 输入框
        self.inputTextField = [[UITextField alloc] init];
        self.inputTextField.backgroundColor = [UIColor whiteColor];
        self.inputTextField.textColor = [UIColor blackColor];
        self.inputTextField.font = [UIFont systemFontOfSize:14];
        self.inputTextField.text = @"12";
        self.inputTextField.textAlignment = NSTextAlignmentCenter;
        self.inputTextField.layer.borderWidth = 0;
        [self.contentView addSubview:self.inputTextField];
        
        // 确认按钮
        self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.confirmButton setTitle:@"获取" forState:UIControlStateNormal];
        [self.confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.confirmButton.backgroundColor = [UIColor systemBlueColor];
        [self.confirmButton addTarget:self action:@selector(confirmButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.confirmButton];
        
        // 取消按钮
        self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.cancelButton setTitle:@"取消" forState:UIControlStateNormal];
        [self.cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.cancelButton.backgroundColor = [UIColor systemGrayColor];
        [self.cancelButton addTarget:self action:@selector(cancelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.cancelButton];
        
        [self setupConstraints];
    }
    return self;
}

- (void)setupConstraints {
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 内容视图约束
        [self.contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.contentView.widthAnchor constraintEqualToConstant:220],
        [self.contentView.heightAnchor constraintEqualToConstant:120],
        
        // 标题标签约束
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        
        // 输入框约束
        [self.inputTextField.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:10],
        [self.inputTextField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.inputTextField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.inputTextField.heightAnchor constraintEqualToConstant:30],
        
        // 按钮约束
        [self.cancelButton.topAnchor constraintEqualToAnchor:self.inputTextField.bottomAnchor constant:10],
        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [self.cancelButton.widthAnchor constraintEqualToConstant:95],
        [self.cancelButton.heightAnchor constraintEqualToConstant:35],
        
        [self.confirmButton.topAnchor constraintEqualToAnchor:self.inputTextField.bottomAnchor constant:10],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.confirmButton.widthAnchor constraintEqualToConstant:95],
        [self.confirmButton.heightAnchor constraintEqualToConstant:35],
    ]];
}

- (void)showInView:(UIView *)view {
    [view addSubview:self];
    
    // 添加动画效果
    self.alpha = 0;
    self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1;
        self.contentView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        // 等动画完成后，延迟一小段时间再弹出键盘，确保视图已经完全布局
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.inputTextField becomeFirstResponder];
        });
    }];
}

- (void)hide {
    [self.inputTextField resignFirstResponder];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)confirmButtonTapped {
    NSInteger length = [self.inputTextField.text integerValue];
    if (length < 1) length = 1;
    if (length > 32) length = 32;
    
    if ([self.delegate respondsToSelector:@selector(patternLengthView:didConfirmWithLength:address:instruction:disassembly:)]) {
        [self.delegate patternLengthView:self 
                     didConfirmWithLength:length 
                                address:self.address 
                           instruction:self.instruction 
                           disassembly:self.disassembly];
    }
    [self hide];
}

- (void)cancelButtonTapped {
    [self hide];
}

- (void)dealloc {
    // 移除键盘通知观察
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 添加键盘显示处理方法
- (void)keyboardWillShow:(NSNotification *)notification {
    // 获取键盘信息
    NSDictionary *info = [notification userInfo];
    CGSize keyboardSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat keyboardHeight = keyboardSize.height;
    
    // 获取输入框在屏幕中的位置
    CGRect textFieldRect = [self.inputTextField.superview convertRect:self.inputTextField.frame toView:nil];
    CGFloat textFieldBottom = textFieldRect.origin.y + textFieldRect.size.height;
    
    // 计算键盘顶部到输入框底部的距离
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat offset = textFieldBottom - (screenHeight - keyboardHeight);
    
    // 如果输入框被键盘遮挡，向上移动视图
    if (offset > 0) {
        // 记录原始位置（如果还没有记录）
        if (CGRectIsNull(self.originalContainerFrame)) {
            self.originalContainerFrame = self.contentView.frame;
        }
        
        // 使用动画移动视图
        [UIView animateWithDuration:0.3 animations:^{
            CGRect newFrame = self.contentView.frame;
            newFrame.origin.y -= offset + 10; // 额外加10点空间
            self.contentView.frame = newFrame;
        }];
    }
}

// 添加键盘隐藏处理方法
- (void)keyboardWillHide:(NSNotification *)notification {
    // 如果有记录原始位置，恢复到原始位置
    if (!CGRectIsNull(self.originalContainerFrame)) {
        [UIView animateWithDuration:0.3 animations:^{
            self.contentView.frame = self.originalContainerFrame;
        }];
    }
}

@end

// 添加特征码结果弹框实现
@interface SSPatternResultView ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextView *patternTextView;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIButton *duplicateButton;

@end

@implementation SSPatternResultView

- (instancetype)initWithPattern:(NSString *)pattern {
    if (self = [super init]) {
        self.frame = [UIScreen mainScreen].bounds;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
        
        // 创建内容视图
        self.contentView = [[UIView alloc] init];
        self.contentView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
        [self addSubview:self.contentView];
        
        // 标题标签
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.text = @"特征码结果";
        self.titleLabel.font = [UIFont systemFontOfSize:14];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.titleLabel];
        
        // 特征码文本视图
        self.patternTextView = [[UITextView alloc] init];
        self.patternTextView.backgroundColor = [UIColor whiteColor];
        self.patternTextView.textColor = [UIColor blackColor];
        self.patternTextView.font = [UIFont fontWithName:@"Menlo" size:14];
        self.patternTextView.text = pattern;
        self.patternTextView.editable = NO;
        self.patternTextView.layer.borderWidth = 0;
        [self.contentView addSubview:self.patternTextView];
        
        // 复制按钮
        self.duplicateButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.duplicateButton setTitle:@"复制" forState:UIControlStateNormal];
        [self.duplicateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.duplicateButton.backgroundColor = [UIColor systemOrangeColor];
        [self.duplicateButton addTarget:self action:@selector(duplicateButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.duplicateButton];
        
        // 确认按钮
        self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.confirmButton setTitle:@"确认" forState:UIControlStateNormal];
        [self.confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.confirmButton.backgroundColor = [UIColor systemBlueColor];
        [self.confirmButton addTarget:self action:@selector(confirmButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.confirmButton];
        
        [self setupConstraints];
    }
    return self;
}

- (void)setupConstraints {
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.patternTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.duplicateButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 内容视图约束
        [self.contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.contentView.widthAnchor constraintEqualToConstant:220],
        [self.contentView.heightAnchor constraintEqualToConstant:180],  // 改为180
        
        // 标题标签约束
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        
        // 文本视图约束
        [self.patternTextView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:10],
        [self.patternTextView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.patternTextView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.patternTextView.heightAnchor constraintEqualToConstant:90],  // 增加到90
        
        // 按钮约束
        [self.duplicateButton.topAnchor constraintEqualToAnchor:self.patternTextView.bottomAnchor constant:10],
        [self.duplicateButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [self.duplicateButton.widthAnchor constraintEqualToConstant:95],
        [self.duplicateButton.heightAnchor constraintEqualToConstant:35],
        
        [self.confirmButton.topAnchor constraintEqualToAnchor:self.patternTextView.bottomAnchor constant:10],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.confirmButton.widthAnchor constraintEqualToConstant:95],
        [self.confirmButton.heightAnchor constraintEqualToConstant:35],
    ]];
}

- (void)showInView:(UIView *)view {
    [view addSubview:self];
    
    // 添加动画效果
    self.alpha = 0;
    self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1;
        self.contentView.transform = CGAffineTransformIdentity;
    }];
}

- (void)hide {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)duplicateButtonTapped {
    if ([self.delegate respondsToSelector:@selector(patternResultViewDidCopy:)]) {
        [self.delegate patternResultViewDidCopy:self];
    }
}

- (void)confirmButtonTapped {
    if ([self.delegate respondsToSelector:@selector(patternResultViewDidConfirm:)]) {
        [self.delegate patternResultViewDidConfirm:self];
    }
    [self hide];
}

@end 