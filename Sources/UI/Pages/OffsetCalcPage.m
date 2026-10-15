#import "UI/Pages/OffsetCalcPage.h"
#import "Services/ModuleViewer.h"
#import "Services/LogService.h"
#import "UI/Components/ThemeConfig.h"

@interface OffsetCalcPage () <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITextField *baseAddressField;
@property (nonatomic, strong) UITextField *offsetField;
@property (nonatomic, strong) UISegmentedControl *calcTypeControl;
@property (nonatomic, strong) UIButton *calcButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *resultCopyBtn;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) UITableView *historyTable;
@property (nonatomic, strong) NSMutableArray *calcHistory;

@end

@implementation OffsetCalcPage

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"偏移计算器";
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    self.calcHistory = [NSMutableArray array];
    
    [self setupUI];
}

- (void)setupUI {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = IMGUI_BG_COLOR;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];
    
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setTitle:@"返回" forState:UIControlStateNormal];
    [self.backButton setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:self.backButton];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"偏移计算器";
    titleLabel.textColor = IMGUI_TEXT;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:titleLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:44],
        
        [self.backButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10],
        [self.backButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.backButton.widthAnchor constraintEqualToConstant:60],
        
        [titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
    ]];
    
    UIView *inputView = [[UIView alloc] init];
    inputView.backgroundColor = IMGUI_BG_COLOR;
    inputView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:inputView];
    
    UILabel *baseLabel = [[UILabel alloc] init];
    baseLabel.text = @"基址/起始地址";
    baseLabel.font = [UIFont systemFontOfSize:14];
    baseLabel.textColor = IMGUI_TEXT;
    baseLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [inputView addSubview:baseLabel];
    
    self.baseAddressField = [[UITextField alloc] init];
    self.baseAddressField.placeholder = @"例如: 0x100000000 或模块名";
    self.baseAddressField.borderStyle = UITextBorderStyleRoundedRect;
    self.baseAddressField.font = [UIFont fontWithName:@"Menlo" size:14];
    self.baseAddressField.keyboardType = UIKeyboardTypeASCIICapable;
    self.baseAddressField.backgroundColor = IMGUI_FRAME_BG;
    self.baseAddressField.textColor = IMGUI_TEXT;
    self.baseAddressField.delegate = self;
    self.baseAddressField.translatesAutoresizingMaskIntoConstraints = NO;
    [inputView addSubview:self.baseAddressField];
    
    UILabel *offsetLabel = [[UILabel alloc] init];
    offsetLabel.text = @"偏移值";
    offsetLabel.font = [UIFont systemFontOfSize:14];
    offsetLabel.textColor = IMGUI_TEXT;
    offsetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [inputView addSubview:offsetLabel];
    
    self.offsetField = [[UITextField alloc] init];
    self.offsetField.placeholder = @"例如: 0x1234";
    self.offsetField.borderStyle = UITextBorderStyleRoundedRect;
    self.offsetField.font = [UIFont fontWithName:@"Menlo" size:14];
    self.offsetField.keyboardType = UIKeyboardTypeASCIICapable;
    self.offsetField.backgroundColor = IMGUI_FRAME_BG;
    self.offsetField.textColor = IMGUI_TEXT;
    self.offsetField.delegate = self;
    self.offsetField.translatesAutoresizingMaskIntoConstraints = NO;
    [inputView addSubview:self.offsetField];
    
    UILabel *calcTypeLabel = [[UILabel alloc] init];
    calcTypeLabel.text = @"计算方式";
    calcTypeLabel.font = [UIFont systemFontOfSize:14];
    calcTypeLabel.textColor = IMGUI_TEXT;
    calcTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [inputView addSubview:calcTypeLabel];
    
    self.calcTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"+ 加偏移", @"- 减偏移"]];
    self.calcTypeControl.selectedSegmentIndex = 0;
    self.calcTypeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [inputView addSubview:self.calcTypeControl];
    
    self.calcButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.calcButton setTitle:@"计算" forState:UIControlStateNormal];
    [self.calcButton setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    self.calcButton.backgroundColor = [UIColor systemBlueColor];
    self.calcButton.layer.cornerRadius = 4;
    self.calcButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.calcButton addTarget:self action:@selector(calcButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputView addSubview:self.calcButton];
    self.calcButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearButton setTitle:@"清空" forState:UIControlStateNormal];
    [self.clearButton setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    self.clearButton.backgroundColor = [UIColor systemGrayColor];
    self.clearButton.layer.cornerRadius = 4;
    self.clearButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.clearButton addTarget:self action:@selector(clearButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputView addSubview:self.clearButton];
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.resultCopyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resultCopyBtn setTitle:@"复制结果" forState:UIControlStateNormal];
    [self.resultCopyBtn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    self.resultCopyBtn.backgroundColor = [UIColor systemGreenColor];
    self.resultCopyBtn.layer.cornerRadius = 4;
    self.resultCopyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.resultCopyBtn addTarget:self action:@selector(copyResultButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputView addSubview:self.resultCopyBtn];
    self.resultCopyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [inputView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
        [inputView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [inputView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        
        [baseLabel.topAnchor constraintEqualToAnchor:inputView.topAnchor],
        [baseLabel.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor],
        
        [self.baseAddressField.topAnchor constraintEqualToAnchor:baseLabel.bottomAnchor constant:5],
        [self.baseAddressField.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor],
        [self.baseAddressField.trailingAnchor constraintEqualToAnchor:inputView.trailingAnchor],
        [self.baseAddressField.heightAnchor constraintEqualToConstant:36],
        
        [offsetLabel.topAnchor constraintEqualToAnchor:self.baseAddressField.bottomAnchor constant:10],
        [offsetLabel.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor],
        
        [self.offsetField.topAnchor constraintEqualToAnchor:offsetLabel.bottomAnchor constant:5],
        [self.offsetField.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor],
        [self.offsetField.trailingAnchor constraintEqualToAnchor:inputView.trailingAnchor],
        [self.offsetField.heightAnchor constraintEqualToConstant:36],
        
        [calcTypeLabel.topAnchor constraintEqualToAnchor:self.offsetField.bottomAnchor constant:10],
        [calcTypeLabel.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor],
        
        [self.calcTypeControl.topAnchor constraintEqualToAnchor:calcTypeLabel.bottomAnchor constant:5],
        [self.calcTypeControl.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor],
        [self.calcTypeControl.trailingAnchor constraintEqualToAnchor:inputView.trailingAnchor],
        [self.calcTypeControl.heightAnchor constraintEqualToConstant:32],
        
        [self.calcButton.topAnchor constraintEqualToAnchor:self.calcTypeControl.bottomAnchor constant:15],
        [self.calcButton.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor],
        [self.calcButton.widthAnchor constraintEqualToAnchor:inputView.widthAnchor multiplier:0.33 constant:-5],
        [self.calcButton.heightAnchor constraintEqualToConstant:40],
        
        [self.clearButton.topAnchor constraintEqualToAnchor:self.calcTypeControl.bottomAnchor constant:15],
        [self.clearButton.leadingAnchor constraintEqualToAnchor:self.calcButton.trailingAnchor constant:5],
        [self.clearButton.widthAnchor constraintEqualToAnchor:inputView.widthAnchor multiplier:0.33 constant:-5],
        [self.clearButton.heightAnchor constraintEqualToConstant:40],
        
        [self.resultCopyBtn.topAnchor constraintEqualToAnchor:self.calcTypeControl.bottomAnchor constant:15],
        [self.resultCopyBtn.leadingAnchor constraintEqualToAnchor:self.clearButton.trailingAnchor constant:5],
        [self.resultCopyBtn.trailingAnchor constraintEqualToAnchor:inputView.trailingAnchor],
        [self.resultCopyBtn.heightAnchor constraintEqualToConstant:40],
    ]];
    
    self.resultLabel = [[UILabel alloc] init];
    self.resultLabel.text = @"等待计算...";
    self.resultLabel.font = [UIFont fontWithName:@"Menlo" size:16];
    self.resultLabel.textColor = [UIColor systemYellowColor];
    self.resultLabel.textAlignment = NSTextAlignmentCenter;
    self.resultLabel.numberOfLines = 0;
    self.resultLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.resultLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.resultLabel.topAnchor constraintEqualToAnchor:inputView.bottomAnchor constant:15],
        [self.resultLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.resultLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.resultLabel.heightAnchor constraintGreaterThanOrEqualToConstant:40]
    ]];
    
    UILabel *historyLabel = [[UILabel alloc] init];
    historyLabel.text = @"计算历史";
    historyLabel.font = [UIFont boldSystemFontOfSize:14];
    historyLabel.textColor = IMGUI_TEXT;
    historyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:historyLabel];
    
    self.historyTable = [[UITableView alloc] init];
    self.historyTable.delegate = self;
    self.historyTable.dataSource = self;
    self.historyTable.backgroundColor = IMGUI_BG_COLOR;
    self.historyTable.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    [self.historyTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"HistoryCell"];
    [self.view addSubview:self.historyTable];
    self.historyTable.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [historyLabel.topAnchor constraintEqualToAnchor:self.resultLabel.bottomAnchor constant:15],
        [historyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        
        [self.historyTable.topAnchor constraintEqualToAnchor:historyLabel.bottomAnchor constant:5],
        [self.historyTable.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.historyTable.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.historyTable.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)backTapped {
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (uint64_t)parseAddress:(NSString *)addrStr {
    if (addrStr.length == 0) return 0;
    
    if ([addrStr hasPrefix:@"0x"] || [addrStr hasPrefix:@"0X"]) {
        uint64_t value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:addrStr];
        [scanner scanHexLongLong:&value];
        return value;
    }
    
    ModuleInfo *module = [[ModuleViewer sharedInstance] getModuleByName:addrStr];
    if (module) {
        return module.baseAddress;
    }
    
    return [addrStr longLongValue];
}

- (void)calcButtonTapped {
    NSString *baseStr = [self.baseAddressField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *offsetStr = [self.offsetField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if (baseStr.length == 0 || offsetStr.length == 0) {
        [self showAlert:@"错误" message:@"请输入基址和偏移值"];
        return;
    }
    
    uint64_t baseAddr = [self parseAddress:baseStr];
    uint64_t offset = [self parseAddress:offsetStr];
    
    if (baseAddr == 0) {
        [self showAlert:@"错误" message:@"无效的基址格式"];
        return;
    }
    
    uint64_t result = 0;
    NSString *formula = @"";
    
    if (self.calcTypeControl.selectedSegmentIndex == 0) {
        result = baseAddr + offset;
        formula = [NSString stringWithFormat:@"0x%llX + 0x%llX = 0x%llX", baseAddr, offset, result];
    } else {
        if (offset > baseAddr) {
            [self showAlert:@"错误" message:@"偏移值不能大于基址"];
            return;
        }
        result = baseAddr - offset;
        formula = [NSString stringWithFormat:@"0x%llX - 0x%llX = 0x%llX", baseAddr, offset, result];
    }
    
    self.resultLabel.text = formula;
    
    [self.calcHistory insertObject:formula atIndex:0];
    if (self.calcHistory.count > 50) {
        [self.calcHistory removeLastObject];
    }
    [self.historyTable reloadData];
    
    [LoggingService log:@"[偏移计算] %@", formula];
}

- (void)clearButtonTapped {
    self.baseAddressField.text = @"";
    self.offsetField.text = @"";
    self.resultLabel.text = @"等待计算...";
}

- (void)copyResultButtonTapped {
    if (self.resultLabel.text.length > 0 && ![self.resultLabel.text isEqualToString:@"等待计算..."]) {
        NSRange range = [self.resultLabel.text rangeOfString:@"= "];
        if (range.location != NSNotFound) {
            NSString *result = [self.resultLabel.text substringFromIndex:range.location + 2];
            [UIPasteboard generalPasteboard].string = result;
            [self showAlert:@"已复制" message:result];
        }
    } else {
        [self showAlert:@"提示" message:@"没有可复制的结果"];
    }
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.calcHistory.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HistoryCell" forIndexPath:indexPath];
    
    if (indexPath.row < self.calcHistory.count) {
        cell.backgroundColor = IMGUI_BG_COLOR;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = self.calcHistory[indexPath.row];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:12];
        cell.textLabel.textColor = IMGUI_TEXT;
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row < self.calcHistory.count) {
        NSString *formula = self.calcHistory[indexPath.row];
        [UIPasteboard generalPasteboard].string = formula;
        [self showAlert:@"已复制" message:formula];
    }
}

@end
