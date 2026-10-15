#import "UI/Dialogs/EditInstructionDialog.h"

@interface SSInstructionEditView ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *currentInstructionLabel;
@property (nonatomic, strong) UITextField *inputTextField;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, assign) CGRect originalFrame;

@end

@implementation SSInstructionEditView

- (instancetype)initWithAddress:(uint64_t)address currentInstruction:(NSString *)instruction {
    if (self = [super init]) {
        self.address = address;
        self.frame = [UIScreen mainScreen].bounds;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
        
        // 创建内容视图
        self.contentView = [[UIView alloc] init];
        self.contentView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
        [self addSubview:self.contentView];
        
        // 当前指令标签
        self.currentInstructionLabel = [[UILabel alloc] init];
        self.currentInstructionLabel.textColor = [UIColor whiteColor];
        self.currentInstructionLabel.text = [NSString stringWithFormat:@"当前指令: %@", instruction];
        self.currentInstructionLabel.font = [UIFont systemFontOfSize:14];
        self.currentInstructionLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.currentInstructionLabel];
        
        // 输入框
        self.inputTextField = [[UITextField alloc] init];
        self.inputTextField.backgroundColor = [UIColor whiteColor];
        self.inputTextField.textColor = [UIColor blackColor];
        self.inputTextField.font = [UIFont systemFontOfSize:14];
        self.inputTextField.text = instruction;
        self.inputTextField.textAlignment = NSTextAlignmentCenter;
        self.inputTextField.layer.borderWidth = 0;
        [self.contentView addSubview:self.inputTextField];
        
        // 确认按钮
        self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.confirmButton setTitle:@"修改" forState:UIControlStateNormal];
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
        
        // 注册键盘通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(keyboardWillShow:)
                                                   name:UIKeyboardWillShowNotification
                                                 object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(keyboardWillHide:)
                                                   name:UIKeyboardWillHideNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    // 移除通知观察者
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupConstraints {
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.currentInstructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 内容视图约束
        [self.contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.contentView.widthAnchor constraintEqualToConstant:220],
        [self.contentView.heightAnchor constraintEqualToConstant:120],
        
        // 当前指令标签约束
        [self.currentInstructionLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.currentInstructionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.currentInstructionLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        
        // 输入框约束
        [self.inputTextField.topAnchor constraintEqualToAnchor:self.currentInstructionLabel.bottomAnchor constant:10],
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

- (void)keyboardWillShow:(NSNotification *)notification {
    // 获取键盘信息
    NSDictionary *info = [notification userInfo];
    CGSize keyboardSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat keyboardHeight = keyboardSize.height;
    
    // 获取输入框在屏幕上的位置
    CGRect textFieldRect = [self.inputTextField convertRect:self.inputTextField.bounds toView:nil];
    CGFloat textFieldBottom = textFieldRect.origin.y + textFieldRect.size.height;
    
    // 计算键盘顶部到输入框底部的距离
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat offset = textFieldBottom - (screenHeight - keyboardHeight);
    
    // 如果输入框被键盘遮挡，向上移动视图
    if (offset > 0) {
        // 保存原始位置
        self.originalFrame = self.contentView.frame;
        
        [UIView animateWithDuration:0.3 animations:^{
            CGRect newFrame = self.contentView.frame;
            newFrame.origin.y -= offset + 20; // 额外加20点空间
            self.contentView.frame = newFrame;
        }];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    // 如果有保存原始位置，恢复到原始位置
    if (!CGRectEqualToRect(self.originalFrame, CGRectZero)) {
        [UIView animateWithDuration:0.3 animations:^{
            self.contentView.frame = self.originalFrame;
        }];
    }
}

- (void)showInView:(UIView *)view {
    [view addSubview:self];
    self.frame = [UIScreen mainScreen].bounds; // 设置为全屏
    
    // 添加动画效果
    self.alpha = 0;
    self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1;
        self.contentView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        // 在动画完成后让输入框成为第一响应者
        [self.inputTextField becomeFirstResponder];
    }];
    
    // 保存原始frame
    self.originalFrame = self.contentView.frame;
}

- (void)hide {
    [self.inputTextField resignFirstResponder]; // 隐藏键盘
    
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)confirmButtonTapped {
    if ([self.delegate respondsToSelector:@selector(instructionEditView:didConfirmWithInstruction:address:)]) {
        [self.delegate instructionEditView:self 
                    didConfirmWithInstruction:self.inputTextField.text 
                                    address:self.address];
    }
    [self hide];
}

- (void)cancelButtonTapped {
    [self hide];
}

@end 