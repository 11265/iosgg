#import "UI/Pages/RemoteCallPage.h"
#import "UI/Components/ThemeConfig.h"
#import "Services/LogService.h"
#import "Services/ProcessMemory.h"
#import "Services/Debugger/SSDebugger.h"
#import "Services/Remote/RemoteCallEngine.h"
#import <mach/mach.h>

typedef NS_ENUM(NSInteger, ParameterType) {
    ParameterTypeInt32 = 0,
    ParameterTypeInt64,
    ParameterTypeFloat,
    ParameterTypeDouble,
    ParameterTypePointer,
    ParameterTypeString
};

@interface ParameterCell : UITableViewCell
@property (nonatomic, strong) UILabel *indexLabel;
@property (nonatomic, strong) UITextField *valueTextField;
@property (nonatomic, strong) UIButton *typeButton;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) ParameterType paramType;
@end

@implementation ParameterCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        self.indexLabel = [[UILabel alloc] init];
        self.indexLabel.font = [AppTheme monospaceFont:14];
        self.indexLabel.textColor = [AppTheme textDisabledColor];
        self.indexLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.indexLabel];
        
        self.typeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.typeButton setTitle:@"Int32" forState:UIControlStateNormal];
        self.typeButton.titleLabel.font = [AppTheme regularFont:12];
        self.typeButton.backgroundColor = [AppTheme frameBackgroundColor];
        self.typeButton.layer.cornerRadius = 4;
        self.typeButton.layer.borderWidth = 1;
        self.typeButton.layer.borderColor = [AppTheme borderColor].CGColor;
        [self.typeButton setTitleColor:[AppTheme checkmarkColor] forState:UIControlStateNormal];
        self.typeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.typeButton];
        
        self.valueTextField = [[UITextField alloc] init];
        self.valueTextField.font = [AppTheme monospaceFont:14];
        self.valueTextField.textColor = [AppTheme textColor];
        self.valueTextField.backgroundColor = [AppTheme frameBackgroundColor];
        self.valueTextField.layer.cornerRadius = 4;
        self.valueTextField.layer.borderWidth = 1;
        self.valueTextField.layer.borderColor = [AppTheme borderColor].CGColor;
        self.valueTextField.layer.sublayerTransform = CATransform3DMakeTranslation(8, 0, 0);
        self.valueTextField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        self.valueTextField.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.valueTextField];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.indexLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [self.indexLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.indexLabel.widthAnchor constraintEqualToConstant:30],
            
            [self.typeButton.leadingAnchor constraintEqualToAnchor:self.indexLabel.trailingAnchor constant:8],
            [self.typeButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.typeButton.widthAnchor constraintEqualToConstant:80],
            [self.typeButton.heightAnchor constraintEqualToConstant:30],
            
            [self.valueTextField.leadingAnchor constraintEqualToAnchor:self.typeButton.trailingAnchor constant:8],
            [self.valueTextField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [self.valueTextField.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.valueTextField.heightAnchor constraintEqualToConstant:30]
        ]];
        
        self.paramType = ParameterTypeInt32;
    }
    return self;
}

@end

@interface RemoteCallPage () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>

@property (nonatomic, strong, readwrite) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UITextField *addressTextField;
@property (nonatomic, strong) UIButton *addParamButton;
@property (nonatomic, strong) UIButton *callButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *memoryTestButton;
@property (nonatomic, strong) UITextView *resultTextView;

@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *parameters;

@end

@implementation RemoteCallPage

- (instancetype)init {
    if (self = [super init]) {
        _parameters = [NSMutableArray array];
        [_parameters addObject:[NSMutableDictionary dictionary]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = IMGUI_BG_COLOR;
    self.title = @"远程调用";
    
    [self setupHeader];
    [self setupControlView];
    [self setupTableView];
    [self setupResultView];
}

- (void)setupHeader {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = IMGUI_BG_COLOR;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];
    
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [backBtn setTitle:@"返回" forState:UIControlStateNormal];
    [backBtn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [backBtn addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:backBtn];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"远程调用";
    titleLabel.textColor = IMGUI_TEXT;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:titleLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:44],
        
        [backBtn.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10],
        [backBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        
        [titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
    ]];
    
    self.headerView = header;
}

- (void)setupControlView {
    UIView *controlView = [[UIView alloc] init];
    controlView.backgroundColor = IMGUI_BG_COLOR;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controlView];
    
    UILabel *addressLabel = [[UILabel alloc] init];
    addressLabel.text = @"函数地址:";
    addressLabel.font = [UIFont systemFontOfSize:14];
    addressLabel.textColor = IMGUI_TEXT;
    addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:addressLabel];
    
    self.addressTextField = [[UITextField alloc] init];
    self.addressTextField.font = [UIFont fontWithName:@"Menlo" size:14];
    self.addressTextField.textColor = IMGUI_TEXT;
    self.addressTextField.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
    self.addressTextField.layer.cornerRadius = 4;
    self.addressTextField.layer.borderWidth = 1;
    self.addressTextField.layer.borderColor = [UIColor colorWithWhite:0.3f alpha:1.0f].CGColor;
    self.addressTextField.layer.sublayerTransform = CATransform3DMakeTranslation(8, 0, 0);
    self.addressTextField.placeholder = @"0x123456789";
    self.addressTextField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.addressTextField.delegate = self;
    self.addressTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:self.addressTextField];
    
    self.addParamButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.addParamButton setTitle:@"+ 添加参数" forState:UIControlStateNormal];
    self.addParamButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.addParamButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    self.addParamButton.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
    self.addParamButton.layer.cornerRadius = 4;
    self.addParamButton.layer.borderWidth = 1;
    self.addParamButton.layer.borderColor = [UIColor colorWithWhite:0.3f alpha:1.0f].CGColor;
    [self.addParamButton addTarget:self action:@selector(addParameter) forControlEvents:UIControlEventTouchUpInside];
    self.addParamButton.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:self.addParamButton];
    
    self.callButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.callButton setTitle:@"执行调用" forState:UIControlStateNormal];
    self.callButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.callButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.callButton.backgroundColor = [UIColor systemBlueColor];
    self.callButton.layer.cornerRadius = 4;
    [self.callButton addTarget:self action:@selector(executeCall) forControlEvents:UIControlEventTouchUpInside];
    self.callButton.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:self.callButton];
    
    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearButton setTitle:@"清空" forState:UIControlStateNormal];
    self.clearButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.clearButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.clearButton.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
    self.clearButton.layer.cornerRadius = 4;
    self.clearButton.layer.borderWidth = 1;
    self.clearButton.layer.borderColor = [UIColor colorWithWhite:0.3f alpha:1.0f].CGColor;
    [self.clearButton addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:self.clearButton];
    
    self.memoryTestButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.memoryTestButton setTitle:@"内存测试" forState:UIControlStateNormal];
    self.memoryTestButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.memoryTestButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.memoryTestButton.backgroundColor = [UIColor systemPurpleColor];
    self.memoryTestButton.layer.cornerRadius = 4;
    [self.memoryTestButton addTarget:self action:@selector(runMemoryTest) forControlEvents:UIControlEventTouchUpInside];
    self.memoryTestButton.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:self.memoryTestButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [controlView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [controlView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [controlView.heightAnchor constraintEqualToConstant:200],
        
        [addressLabel.topAnchor constraintEqualToAnchor:controlView.topAnchor constant:10],
        [addressLabel.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor],
        
        [self.addressTextField.topAnchor constraintEqualToAnchor:addressLabel.bottomAnchor constant:8],
        [self.addressTextField.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor],
        [self.addressTextField.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor],
        [self.addressTextField.heightAnchor constraintEqualToConstant:30],
        
        [self.addParamButton.topAnchor constraintEqualToAnchor:self.addressTextField.bottomAnchor constant:10],
        [self.addParamButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor],
        [self.addParamButton.widthAnchor constraintEqualToConstant:100],
        [self.addParamButton.heightAnchor constraintEqualToConstant:30],
        
        [self.clearButton.topAnchor constraintEqualToAnchor:self.addressTextField.bottomAnchor constant:10],
        [self.clearButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor],
        [self.clearButton.widthAnchor constraintEqualToConstant:60],
        [self.clearButton.heightAnchor constraintEqualToConstant:30],
        
        [self.callButton.topAnchor constraintEqualToAnchor:self.addParamButton.bottomAnchor constant:10],
        [self.callButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor],
        [self.callButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor],
        [self.callButton.heightAnchor constraintEqualToConstant:35],
        
        [self.memoryTestButton.topAnchor constraintEqualToAnchor:self.callButton.bottomAnchor constant:10],
        [self.memoryTestButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor],
        [self.memoryTestButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor],
        [self.memoryTestButton.heightAnchor constraintEqualToConstant:35]
    ]];
    
    self.headerView = controlView;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = IMGUI_BG_COLOR;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.tableView.rowHeight = 50;
    self.tableView.estimatedRowHeight = 50;
    [self.tableView registerClass:[ParameterCell class] forCellReuseIdentifier:@"ParameterCell"];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.layer.borderColor = [UIColor colorWithWhite:0.3f alpha:1.0f].CGColor;
    self.tableView.layer.borderWidth = 1;
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:5],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.tableView.heightAnchor constraintEqualToConstant:200]
    ]];
}

- (void)setupResultView {
    UILabel *resultLabel = [[UILabel alloc] init];
    resultLabel.text = @"返回值:";
    resultLabel.font = [UIFont systemFontOfSize:14];
    resultLabel.textColor = IMGUI_TEXT;
    resultLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:resultLabel];
    
    self.resultTextView = [[UITextView alloc] init];
    self.resultTextView.font = [UIFont fontWithName:@"Menlo" size:12];
    self.resultTextView.textColor = IMGUI_TEXT;
    self.resultTextView.backgroundColor = [UIColor colorWithWhite:0.1f alpha:1.0f];
    self.resultTextView.layer.cornerRadius = 4;
    self.resultTextView.layer.borderWidth = 1;
    self.resultTextView.layer.borderColor = [UIColor colorWithWhite:0.3f alpha:1.0f].CGColor;
    self.resultTextView.editable = NO;
    self.resultTextView.text = @"等待执行...";
    self.resultTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.resultTextView];
    
    [NSLayoutConstraint activateConstraints:@[
        [resultLabel.topAnchor constraintEqualToAnchor:self.tableView.bottomAnchor constant:10],
        [resultLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        
        [self.resultTextView.topAnchor constraintEqualToAnchor:resultLabel.bottomAnchor constant:5],
        [self.resultTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.resultTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.resultTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.parameters.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ParameterCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ParameterCell" forIndexPath:indexPath];
    
    cell.index = indexPath.row;
    cell.indexLabel.text = [NSString stringWithFormat:@"参数%ld:", (long)indexPath.row];
    
    NSDictionary *param = self.parameters[indexPath.row];
    NSString *value = param[@"value"] ?: @"";
    cell.valueTextField.text = value;
    
    ParameterType type = [param[@"type"] integerValue];
    cell.paramType = type;
    [cell.typeButton setTitle:[self titleForParameterType:type] forState:UIControlStateNormal];
    
    cell.valueTextField.tag = indexPath.row;
    cell.valueTextField.delegate = self;
    [cell.valueTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    
    [cell.typeButton removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
    [cell.typeButton addTarget:self action:@selector(typeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.typeButton.tag = indexPath.row;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.parameters removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row > 0;
}

#pragma mark - Actions

- (void)backTapped {
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)addParameter {
    [self.parameters addObject:[NSMutableDictionary dictionary]];
    [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.parameters.count - 1 inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)clearAll {
    [self.parameters removeAllObjects];
    [self.parameters addObject:[NSMutableDictionary dictionary]];
    self.addressTextField.text = @"";
    self.resultTextView.text = @"等待执行...";
    [self.tableView reloadData];
}

- (void)textFieldDidChange:(UITextField *)textField {
    if (textField.tag < self.parameters.count) {
        self.parameters[textField.tag][@"value"] = textField.text ?: @"";
    }
}

- (void)typeButtonTapped:(UIButton *)button {
    NSInteger index = button.tag;
    if (index >= self.parameters.count) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择参数类型"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *types = @[@(ParameterTypeInt32), @(ParameterTypeInt64), @(ParameterTypeFloat), @(ParameterTypeDouble), @(ParameterTypePointer), @(ParameterTypeString)];
    NSArray *titles = @[@"Int32", @"Int64", @"Float", @"Double", @"Pointer", @"String"];
    
    for (NSInteger i = 0; i < types.count; i++) {
        [alert addAction:[UIAlertAction actionWithTitle:titles[i]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            self.parameters[index][@"type"] = types[i];
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)titleForParameterType:(ParameterType)type {
    switch (type) {
        case ParameterTypeInt32: return @"Int32";
        case ParameterTypeInt64: return @"Int64";
        case ParameterTypeFloat: return @"Float";
        case ParameterTypeDouble: return @"Double";
        case ParameterTypePointer: return @"Pointer";
        case ParameterTypeString: return @"String";
    }
}

- (void)executeCall {
    NSString *addressString = [self.addressTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (addressString.length == 0) {
        [self showError:@"请输入函数地址"];
        return;
    }
    
    uint64_t address = 0;
    if ([addressString hasPrefix:@"0x"] || [addressString hasPrefix:@"0X"]) {
        NSScanner *scanner = [NSScanner scannerWithString:addressString];
        [scanner scanHexLongLong:&address];
    } else {
        address = [addressString longLongValue];
    }
    
    if (address == 0) {
        [self showError:@"无效的函数地址"];
        return;
    }
    
    [self.resultTextView setText:[NSString stringWithFormat:@"正在调用函数: 0x%llX\n", address]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self performRemoteCall:address];
    });
}

- (void)performRemoteCall:(uint64_t)address {
    @autoreleasepool {
        NSMutableArray<NSNumber *> *params = [NSMutableArray array];
        
        for (NSInteger i = 0; i < MIN(self.parameters.count, 8); i++) {
            NSDictionary *param = self.parameters[i];
            NSString *valueString = param[@"value"] ?: @"0";
            ParameterType type = [param[@"type"] integerValue];
            
            uint64_t value = [self parseValue:valueString type:type];
            [params addObject:@(value)];
        }
        
        [LoggingService log:@"[远程调用] 开始执行: 地址=0x%llX, 参数数量=%ld", address, (long)params.count];
        
        NSError *error = nil;
        uint64_t returnValue = [[RemoteCallEngine sharedInstance] callFunctionAtAddress:address
                                                                              parameters:params
                                                                             paramCount:params.count
                                                                                   error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSString *result = [NSString stringWithFormat:@"调用失败: %@\n\n地址: 0x%llX", error.localizedDescription, address];
                [self.resultTextView setText:result];
                [self showError:error.localizedDescription];
            } else {
                NSString *result = [NSString stringWithFormat:@"调用成功!\n\n地址: 0x%llX\n\n参数:\n", address];
                for (NSInteger i = 0; i < MIN(self.parameters.count, 8); i++) {
                    NSDictionary *param = self.parameters[i];
                    result = [result stringByAppendingFormat:@"X%ld: %@ (%@)\n", (long)i, param[@"value"] ?: @"0", [self titleForParameterType:[param[@"type"] integerValue]]];
                }
                result = [result stringByAppendingFormat:@"\n返回值: 0x%llX", returnValue];
                [self.resultTextView setText:result];
                
                [LoggingService log:@"[远程调用] 调用完成，返回值: 0x%llX", returnValue];
            }
        });
    }
}

- (void)runMemoryTest {
    [self.resultTextView setText:@"正在执行内存call测试...\n\n测试步骤:\n1. 在目标进程分配内存\n2. 写入测试代码 (MOV X0, #0x1234; RET)\n3. 调用测试代码\n4. 验证返回值"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *error = nil;
        uint64_t result = [[RemoteCallEngine sharedInstance] testMemoryCall:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSString *resultText = [NSString stringWithFormat:@"测试失败!\n\n错误: %@\n\n请检查:\n1. 目标进程是否正在运行\n2. 是否有足够的权限", error.localizedDescription];
                [self.resultTextView setText:resultText];
                [self showError:error.localizedDescription];
            } else {
                NSString *resultText = [NSString stringWithFormat:@"测试成功! \n\n测试结果:\n- 分配内存并写入测试代码\n- 执行远程调用\n- 返回值: 0x%llX\n- 期望值: 0x1234\n- 测试通过！\n\n远程调用功能正常工作！", result];
                [self.resultTextView setText:resultText];
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"测试成功"
                                                                               message:@"内存call测试通过！远程调用功能正常工作。"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

- (uint64_t)parseValue:(NSString *)valueString type:(ParameterType)type {
    valueString = [valueString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if ([valueString hasPrefix:@"0x"] || [valueString hasPrefix:@"0X"]) {
        uint64_t value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:valueString];
        [scanner scanHexLongLong:&value];
        return value;
    }
    
    switch (type) {
        case ParameterTypeInt32:
            return (int32_t)[valueString intValue];
        case ParameterTypeInt64:
            return [valueString longLongValue];
        case ParameterTypeFloat: {
            float f = [valueString floatValue];
            return *(uint32_t *)&f;
        }
        case ParameterTypeDouble: {
            double d = [valueString doubleValue];
            return *(uint64_t *)&d;
        }
        case ParameterTypePointer:
            return [valueString longLongValue];
        case ParameterTypeString:
            return (uint64_t)[valueString UTF8String];
    }
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"错误"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    
    [self.resultTextView setText:[NSString stringWithFormat:@"错误: %@", message]];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
