#import "UI/Dialogs/BaseAddressDialog.h"
#import "Services/LogService.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import "Services/ProcessMemory.h"
#import "Services/LogService.h"


@interface SSBaseAddressPopViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) NSLayoutConstraint *contentCenterYConstraint;

@end

@implementation SSBaseAddressPopViewController

+ (instancetype)baseAddressPopViewController {
    return [[SSBaseAddressPopViewController alloc] init];
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
        self.contentCenterYConstraint,
        [self.contentView.widthAnchor constraintEqualToConstant:250],
        [self.contentView.heightAnchor constraintEqualToConstant:200]
    ]];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"基址解析";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:titleLabel];
    
    // 创建搜索输入框
    self.searchTextField = [[UITextField alloc] init];
    self.searchTextField.placeholder = @"请输入地址表达式";
    self.searchTextField.backgroundColor = [UIColor whiteColor];
    self.searchTextField.borderStyle = UITextBorderStyleNone;
    self.searchTextField.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.searchTextField];
    
    // 添加搜索按钮
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [searchButton setTitle:@"解析" forState:UIControlStateNormal];
    searchButton.backgroundColor = [UIColor systemBlueColor];
    [searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [searchButton addTarget:self action:@selector(searchButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:searchButton];
    
    // 添加结果标签
    self.resultLabel = [[UILabel alloc] init];
    self.resultLabel.textColor = [UIColor whiteColor];
    self.resultLabel.textAlignment = NSTextAlignmentCenter;
    self.resultLabel.numberOfLines = 0;
    [self.contentView addSubview:self.resultLabel];
    
    // 设置约束
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchTextField.translatesAutoresizingMaskIntoConstraints = NO;
    searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.resultLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
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
        [searchButton.heightAnchor constraintEqualToConstant:40],
        
        // 结果标签约束
        [self.resultLabel.topAnchor constraintEqualToAnchor:searchButton.bottomAnchor constant:10],
        [self.resultLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [self.resultLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.resultLabel.heightAnchor constraintEqualToConstant:40]
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
    NSString *expression = self.searchTextField.text;
    if (!expression || expression.length == 0) {
        [LoggingService log:@"错误：请输入地址表达式"];
        self.resultLabel.text = @"请输入地址表达式";
        return;
    }
    
    uint64_t currentAddr = 0;
    
    // 首先检查是否是箭头格式的指针链 [Module + Offset] -> +Offset -> ...
    if ([expression containsString:@"->"]) {
        NSArray *components = [expression componentsSeparatedByString:@"->"];
        
        // 1. 解析基址部分: [Module + BaseOffset]
        NSString *baseComponent = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([baseComponent hasPrefix:@"["] && [baseComponent hasSuffix:@"]"]) {
            baseComponent = [baseComponent substringWithRange:NSMakeRange(1, baseComponent.length - 2)]; // Remove []
            
            NSArray *baseParts = [baseComponent componentsSeparatedByString:@"+"];
            if (baseParts.count == 2) {
                NSString *moduleName = [baseParts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *offsetStr = [baseParts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                
                uint64_t moduleBase = [self getModuleBase:moduleName];
                uint64_t baseOffset = strtoull([offsetStr UTF8String], NULL, 16);
                
                currentAddr = moduleBase + baseOffset;
                [LoggingService log:@"[解析] 模块: %@, 基址: 0x%llX, 偏移: 0x%llX -> 0x%llX", moduleName, moduleBase, baseOffset, currentAddr];
            } else {
                self.resultLabel.text = @"格式错误: 基址部分应为 [模块 + 偏移]";
                return;
            }
        } else {
             self.resultLabel.text = @"格式错误: 基址部分缺少 []";
             return;
        }
        
        // 2. 处理后续偏移
        for (NSUInteger i = 1; i < components.count; i++) {
            // 读取当前地址的指针值
            uint64_t pointerValue = 0;
            mach_vm_size_t size = sizeof(uint64_t);
            kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), currentAddr, size, (mach_vm_address_t)&pointerValue, &size);
            
            if (kr != KERN_SUCCESS) {
                [LoggingService log:@"读取地址 0x%llX 失败", currentAddr];
                self.resultLabel.text = [NSString stringWithFormat:@"读取地址 0x%llX 失败", currentAddr];
                return;
            }
            
            NSString *offsetStr = [components[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            // 移除可能存在的 + 号
            offsetStr = [offsetStr stringByReplacingOccurrencesOfString:@"+" withString:@""];
            uint64_t offset = strtoull([offsetStr UTF8String], NULL, 16);
            
            [LoggingService log:@"[解析] 层级 %lu: 读取 0x%llX -> 指针 0x%llX + 偏移 0x%llX", (unsigned long)i, currentAddr, pointerValue, offset];
            
            currentAddr = pointerValue + offset;
        }
    }
    // 检查是否是纯地址格式（以0x开头）
    else if ([expression hasPrefix:@"0x"]) {
        // 检查是否包含偏移
        NSArray *components = [expression componentsSeparatedByString:@"+"];
        currentAddr = strtoull([components[0] UTF8String], NULL, 16);
        [LoggingService log:@"直接使用地址: 0x%llX", currentAddr];
        
        // 处理所有偏移
        for (NSUInteger i = 1; i < components.count; i++) {
            NSString *trimmedOffset = [components[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (![trimmedOffset hasPrefix:@"0x"]) {
                trimmedOffset = [@"0x" stringByAppendingString:trimmedOffset];
            }
            uint64_t offset = strtoull([trimmedOffset UTF8String], NULL, 16);
            currentAddr += offset;
            [LoggingService log:@"添加偏移: 0x%llX, 最终地址: 0x%llX", offset, currentAddr];
        }
    } else {
        // 不是纯地址，尝试解析模块+偏移格式
        NSArray *allComponents = [expression componentsSeparatedByString:@"+"];
        NSString *firstComponent = allComponents[0];
        
        // 检查第一个组件是否是地址（以0x开头）
        if ([firstComponent hasPrefix:@"0x"]) {
            currentAddr = strtoull([firstComponent UTF8String], NULL, 16);
            [LoggingService log:@"使用基址: 0x%llX", currentAddr];
        } else {
            // 不是地址，视为模块名
            currentAddr = [self getModuleBase:firstComponent];
            [LoggingService log:@"使用模块 %@ 的基址: 0x%llX", firstComponent, currentAddr];
        }
        
        // 处理后续的偏移
        for (NSUInteger i = 1; i < allComponents.count; i++) {
            NSString *trimmedOffset = [allComponents[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (![trimmedOffset hasPrefix:@"0x"]) {
                trimmedOffset = [@"0x" stringByAppendingString:trimmedOffset];
            }
            uint64_t offset = strtoull([trimmedOffset UTF8String], NULL, 16);
            currentAddr += offset;
            
            // 如果不是最后一个偏移，需要读取指针指向的地址
            if (i < allComponents.count - 1) {
                uint64_t nextAddr = 0;
                mach_vm_size_t size = sizeof(uint64_t);
                kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                                        currentAddr,
                                                        size,
                                                        (mach_vm_address_t)&nextAddr,
                                                        &size);
                
                if (kr != KERN_SUCCESS) {
                    [LoggingService log:@"读取地址 0x%llX 失败", currentAddr];
                    self.resultLabel.text = [NSString stringWithFormat:@"读取地址 0x%llX 失败", currentAddr];
                    return;
                }
                
                [LoggingService log:@"偏移: 0x%llX, 读取地址: 0x%llX -> 0x%llX", 
                      offset, currentAddr, nextAddr];
                currentAddr = nextAddr;
            } else {
                [LoggingService log:@"最终偏移: 0x%llX, 最终地址: 0x%llX", offset, currentAddr];
            }
        }
    }
    
    // 读取最终地址的 int32 值
    int32_t finalValue = 0;
    mach_vm_size_t size = sizeof(int32_t);
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                            currentAddr,
                                            size,
                                            (mach_vm_address_t)&finalValue,
                                            &size);
    
    if (kr == KERN_SUCCESS) {
        self.resultLabel.text = [NSString stringWithFormat:@"值: %d (0x%X)", finalValue, finalValue];
        [LoggingService log:@"读取值成功 - 地址: 0x%llX, 值: %d", currentAddr, finalValue];
    } else {
        self.resultLabel.text = [NSString stringWithFormat:@"读取地址 0x%llX 失败", currentAddr];
        [LoggingService log:@"读取最终地址 0x%llX 的值失败", currentAddr];
    }
}

// 获取模块基址的方法
- (uint64_t)getModuleBase:(NSString *)moduleName {
    uint32_t count = _dyld_image_count();
    [LoggingService log:@"开始查找模块 %@, 共有 %d 个模块", moduleName, count];
    
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            NSString *imageName = [NSString stringWithUTF8String:name];
            NSString *shortName = [imageName lastPathComponent];
            
            if ([shortName.lowercaseString containsString:moduleName.lowercaseString]) {
                uint64_t baseAddress = (uint64_t)_dyld_get_image_header(i);
                uint64_t slide = (uint64_t)_dyld_get_image_vmaddr_slide(i);
                
                [LoggingService log:@"找到匹配模块: %@", shortName];
                [LoggingService log:@"实际加载基址: 0x%llX, ASLR偏移: 0x%llX", baseAddress, slide];
                
                return baseAddress;
            }
        }
    }
    
    [LoggingService log:@"未找到匹配的模块: %@", moduleName];
    return 0;
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