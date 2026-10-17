#import "UI/Dialogs/AddRecordDialog.h"
#import "UI/Pages/Record/RecordPage.h"
#import "Modules/MemoryAnalysis/PointerChainParser.h"
#import "UI/Components/FloatingWindow.h"
#import "Services/LogService.h"
#import <objc/runtime.h>

@interface SSAddRecordPopViewController ()

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *leftContainerView;
@property (nonatomic, strong) UIView *dataTypeContainer;
@property (nonatomic, strong) UITextField *addressTextField;
@property (nonatomic, strong) NSMutableArray<UIButton *> *typeButtons;
@property (nonatomic, assign) NSInteger selectedTypeIndex;
@property (nonatomic, strong) NSLayoutConstraint *centerYConstraint;
@property (nonatomic, strong) UISegmentedControl *addressTypeSegment;
@property (nonatomic, strong) UILabel *hintLabel;

@end

@implementation SSAddRecordPopViewController

+ (instancetype)addRecordPopViewController {
    return [[SSAddRecordPopViewController alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
    [self.view addGestureRecognizer:tapGesture];
    
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    
    self.containerView = [[UIView alloc] init];
    self.containerView.backgroundColor = [UIColor colorWithRed:240/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
    self.containerView.layer.cornerRadius = 10;
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.containerView];
    
    self.centerYConstraint = [self.containerView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        self.centerYConstraint,
        [self.containerView.widthAnchor constraintEqualToConstant:220],
        [self.containerView.heightAnchor constraintEqualToConstant:200]
    ]];
    
    self.leftContainerView = [[UIView alloc] init];
    self.leftContainerView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    self.leftContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.leftContainerView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.leftContainerView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [self.leftContainerView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [self.leftContainerView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [self.leftContainerView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor]
    ]];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"添加地址";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:14];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leftContainerView addSubview:titleLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.leftContainerView.topAnchor constant:10],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.leftContainerView.centerXAnchor],
    ]];
    
    self.dataTypeContainer = [[UIView alloc] init];
    self.dataTypeContainer.backgroundColor = [UIColor whiteColor];
    self.dataTypeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leftContainerView addSubview:self.dataTypeContainer];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.dataTypeContainer.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10],
        [self.dataTypeContainer.leadingAnchor constraintEqualToAnchor:self.leftContainerView.leadingAnchor],
        [self.dataTypeContainer.trailingAnchor constraintEqualToAnchor:self.leftContainerView.trailingAnchor],
        [self.dataTypeContainer.heightAnchor constraintEqualToConstant:30]
    ]];
    
    self.typeButtons = [NSMutableArray array];
    NSArray *types = @[@"i8", @"i16", @"i32", @"i64", @"f32", @"f64"];
    CGFloat containerWidth = 220.0f;
    CGFloat buttonWidth = containerWidth / types.count;
    
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        [button setTitle:types[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
        button.titleLabel.font = [UIFont systemFontOfSize:12];
        button.backgroundColor = [UIColor whiteColor];
        [button addTarget:self action:@selector(typeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.frame = CGRectMake(buttonWidth * i, 0, buttonWidth, 30);
        [self.dataTypeContainer addSubview:button];
        [self.typeButtons addObject:button];
        
        if (i < types.count - 1) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(buttonWidth * (i + 1), 0, 1, 30)];
            separator.backgroundColor = [UIColor colorWithRed:200/255.0 green:200/255.0 blue:200/255.0 alpha:1.0];
            [self.dataTypeContainer addSubview:separator];
        }
    }
    
    [self selectTypeIndex:2];
    
    self.addressTypeSegment = [[UISegmentedControl alloc] initWithItems:@[@"静态地址", @"指针链"]];
    self.addressTypeSegment.selectedSegmentIndex = 0;
    self.addressTypeSegment.tintColor = [UIColor systemBlueColor];
    self.addressTypeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.addressTypeSegment addTarget:self action:@selector(addressTypeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.leftContainerView addSubview:self.addressTypeSegment];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.addressTypeSegment.topAnchor constraintEqualToAnchor:self.dataTypeContainer.bottomAnchor constant:10],
        [self.addressTypeSegment.leadingAnchor constraintEqualToAnchor:self.leftContainerView.leadingAnchor constant:10],
        [self.addressTypeSegment.trailingAnchor constraintEqualToAnchor:self.leftContainerView.trailingAnchor constant:-10],
        [self.addressTypeSegment.heightAnchor constraintEqualToConstant:28]
    ]];
    
    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.text = @"格式: 0x1000";
    self.hintLabel.font = [UIFont systemFontOfSize:10];
    self.hintLabel.textColor = [UIColor lightGrayColor];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leftContainerView addSubview:self.hintLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.hintLabel.topAnchor constraintEqualToAnchor:self.addressTypeSegment.bottomAnchor constant:2],
        [self.hintLabel.centerXAnchor constraintEqualToAnchor:self.leftContainerView.centerXAnchor]
    ]];
    
    self.addressTextField = [[UITextField alloc] init];
    self.addressTextField.placeholder = @"请输入地址 (如 0x1000)";
    self.addressTextField.borderStyle = UITextBorderStyleNone;
    self.addressTextField.backgroundColor = [UIColor whiteColor];
    self.addressTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.addressTextField.textAlignment = NSTextAlignmentCenter;
    self.addressTextField.keyboardType = UIKeyboardTypeASCIICapable;
    [self.leftContainerView addSubview:self.addressTextField];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.addressTextField.topAnchor constraintEqualToAnchor:self.hintLabel.bottomAnchor constant:5],
        [self.addressTextField.leadingAnchor constraintEqualToAnchor:self.leftContainerView.leadingAnchor],
        [self.addressTextField.trailingAnchor constraintEqualToAnchor:self.leftContainerView.trailingAnchor],
        [self.addressTextField.heightAnchor constraintEqualToConstant:30]
    ]];
    
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cancelButton.backgroundColor = [UIColor systemGrayColor];
    [cancelButton addTarget:self action:@selector(cancelButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftContainerView addSubview:cancelButton];
    
    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [addButton setTitle:@"添加" forState:UIControlStateNormal];
    [addButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    addButton.backgroundColor = [UIColor systemBlueColor];
    [addButton addTarget:self action:@selector(addButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftContainerView addSubview:addButton];
    
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    addButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [cancelButton.topAnchor constraintEqualToAnchor:self.addressTextField.bottomAnchor constant:10],
        [cancelButton.trailingAnchor constraintEqualToAnchor:self.leftContainerView.centerXAnchor constant:-5],
        [cancelButton.widthAnchor constraintEqualToConstant:80],
        [cancelButton.heightAnchor constraintEqualToConstant:35],
        
        [addButton.topAnchor constraintEqualToAnchor:self.addressTextField.bottomAnchor constant:10],
        [addButton.leadingAnchor constraintEqualToAnchor:self.leftContainerView.centerXAnchor constant:5],
        [addButton.widthAnchor constraintEqualToConstant:80],
        [addButton.heightAnchor constraintEqualToConstant:35]
    ]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)typeButtonTapped:(UIButton *)sender {
    [self selectTypeIndex:sender.tag];
}

- (void)selectTypeIndex:(NSInteger)index {
    self.selectedTypeIndex = index;
    for (UIButton *button in self.typeButtons) {
        button.selected = (button.tag == index);
        button.backgroundColor = button.selected ? [UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0] : [UIColor whiteColor];
    }
}

- (void)addressTypeChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0) {
        self.addressTextField.placeholder = @"请输入地址 (如 0x1000)";
        self.hintLabel.text = @"格式: 0x1000";
    } else {
        self.addressTextField.placeholder = @"[main + 0x1000], +0x10, +0x20";
        self.hintLabel.text = @"支持: [模块+偏移], 模块+偏移, [模块], 模块";
    }
}

- (void)cancelButtonTapped:(UIButton *)sender {
    [self dismissSelf];
}

- (void)addButtonTapped:(UIButton *)sender {
    NSString *address = self.addressTextField.text;
    
    if (address.length > 0) {
        NSArray *types = @[@"i8", @"i16", @"i32", @"i64", @"f32", @"f64"];
        NSString *type = types[self.selectedTypeIndex];
        
        RecordPage *recordPage = [FloatingWindow sharedInstance].recordViewController;
        
        if (self.addressTypeSegment.selectedSegmentIndex == 1) {
            NSError *error = nil;
            NSArray *chain = [PointerChainResolver parseChainExpression:address error:&error];
            
            if (error || chain.count == 0) {
                NSString *errorMsg = error.localizedDescription ?: @"无法解析指针链表达式";
                [LoggingService log:@"指针链解析失败: %@", errorMsg];
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"格式错误"
                                                                               message:errorMsg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            if (recordPage) {
                NSDictionary *record = @{
                    @"address": @"",
                    @"type": type,
                    @"isPointerChain": @YES,
                    @"pointerChain": chain,
                    @"chainExpression": address
                };
                [recordPage addAddressesToRecord:@[record]];
                [LoggingService log:@"已添加指针链: %@", address];
            }
        } else {
            if (![address hasPrefix:@"0x"] && ![address hasPrefix:@"0X"]) {
                address = [@"0x" stringByAppendingString:address];
            }
            
            if (recordPage) {
                NSDictionary *record = @{
                    @"address": address,
                    @"type": type,
                    @"isPointerChain": @NO
                };
                [recordPage addAddressesToRecord:@[record]];
                [LoggingService log:@"已添加地址: %@ (%@)", address, type];
            }
        }
        
        [self dismissSelf];
    } else {
        [LoggingService log:@"错误：请输入地址"];
    }
}

- (void)backgroundTapped:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    if (!CGRectContainsPoint(self.containerView.frame, location)) {
        [self dismissSelf];
    } else {
        [self.addressTextField resignFirstResponder];
    }
}

- (void)dismissSelf {
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    CGSize keyboardSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    
    CGRect textFieldRect = [self.addressTextField convertRect:self.addressTextField.bounds toView:self.view];
    CGFloat overlap = CGRectGetMaxY(textFieldRect) - (self.view.bounds.size.height - keyboardSize.height);
    
    if (overlap > 0) {
        self.centerYConstraint.constant = -(overlap + 20);
        [UIView animateWithDuration:0.3 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.centerYConstraint.constant = 0;
    [UIView animateWithDuration:0.3 animations:^{
        [self.view layoutIfNeeded];
    }];
}

@end
