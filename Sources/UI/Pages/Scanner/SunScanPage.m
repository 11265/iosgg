#import "UI/Pages/Scanner/SunScanPage.h"
#import "Modules/Scanner/SunScanner.h"
#import "Services/LogService.h"
#import "Modules/Remote/RemoteCallEngine.h"
#import "UI/Components/ThemeConfig.h"

#pragma mark - 工具

static NSString *SunTypeName(int type) {
    switch (type) {
        case 4: return @"普通 (25)";
        case 5: return @"特殊 (15)";
        case 6: return @"未知";
        default: return [NSString stringWithFormat:@"类型 %d", type];
    }
}

static uint64_t SunParseAddress(NSString *text) {
    NSString *s = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) return 0;
    if ([s hasPrefix:@"0x"] || [s hasPrefix:@"0X"]) {
        uint64_t v = 0;
        NSScanner *scanner = [NSScanner scannerWithString:s];
        [scanner scanHexLongLong:&v];
        return v;
    }
    return (uint64_t)[s longLongValue];
}

#pragma mark - 单元格：一行显示三组参数

@interface SunObjectCell : UITableViewCell
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *typeLabel;
@property (nonatomic, strong) UILabel *fieldLabel;   // 类型@0x74 / 管理器@0x08
@property (nonatomic, strong) UILabel *paramLabel;   // 调用参数 X0
@end

@implementation SunObjectCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        
        self.addressLabel = [self makeLabel:14 color:[AppTheme textColor]];
        self.typeLabel = [self makeLabel:13 color:[AppTheme checkmarkColor]];
        self.typeLabel.textAlignment = NSTextAlignmentRight;
        self.fieldLabel = [self makeLabel:11 color:[AppTheme textDisabledColor]];
        self.paramLabel = [self makeLabel:11 color:[AppTheme valueColor]];
        
        for (UILabel *label in @[self.addressLabel, self.typeLabel, self.fieldLabel, self.paramLabel]) {
            [self.contentView addSubview:label];
        }
        
        [NSLayoutConstraint activateConstraints:@[
            [self.addressLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.addressLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.addressLabel.heightAnchor constraintEqualToConstant:18],
            
            [self.typeLabel.centerYAnchor constraintEqualToAnchor:self.addressLabel.centerYAnchor],
            [self.typeLabel.leadingAnchor constraintEqualToAnchor:self.addressLabel.trailingAnchor constant:8],
            [self.typeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            
            [self.fieldLabel.topAnchor constraintEqualToAnchor:self.addressLabel.bottomAnchor constant:3],
            [self.fieldLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.fieldLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.fieldLabel.heightAnchor constraintEqualToConstant:14],
            
            [self.paramLabel.topAnchor constraintEqualToAnchor:self.fieldLabel.bottomAnchor constant:3],
            [self.paramLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.paramLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.paramLabel.heightAnchor constraintEqualToConstant:14]
        ]];
    }
    return self;
}

- (UILabel *)makeLabel:(CGFloat)size color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = [AppTheme monospaceFont:size];
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

@end

#pragma mark - 页面

@interface SunScannerPage () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>

@property (nonatomic, strong) UITextField *managerBaseField;
@property (nonatomic, strong) UITextField *collectFunctionField;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *quickValidateButton;
@property (nonatomic, strong) UIButton *collectAllButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) NSMutableArray *sunObjects;
@property (nonatomic, assign) uint64_t collectSunFunction;

@end

@implementation SunScannerPage

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"对PVZ调用";
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    self.sunObjects = [NSMutableArray array];
    self.collectSunFunction = 0;
    
    [self setupUI];
}

#pragma mark - UI

- (void)setupUI {
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
    titleLabel.text = @"对PVZ调用";
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
    
    UIView *controlView = [[UIView alloc] init];
    controlView.backgroundColor = IMGUI_BG_COLOR;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controlView];
    
    UILabel *baseLabel = [self makeCaption:@"阳光管理器基址"];
    UILabel *funcLabel = [self makeCaption:@"收取函数地址"];
    [controlView addSubview:baseLabel];
    [controlView addSubview:funcLabel];
    
    self.managerBaseField = [self makeField:@"例如 0x130138000"];
    if (self.sunManagerBase != 0) {
        self.managerBaseField.text = [NSString stringWithFormat:@"0x%llX", self.sunManagerBase];
    }
    [controlView addSubview:self.managerBaseField];
    
    self.collectFunctionField = [self makeField:@"例如 0x1008FD608"];
    [controlView addSubview:self.collectFunctionField];
    
    self.scanButton = [self makeButton:@"扫描阳光对象" color:[UIColor systemBlueColor] action:@selector(scanButtonTapped)];
    [controlView addSubview:self.scanButton];
    
    self.quickValidateButton = [self makeButton:@"快速验证已知地址" color:[UIColor systemPurpleColor] action:@selector(quickValidateButtonTapped)];
    [controlView addSubview:self.quickValidateButton];
    
    self.collectAllButton = [self makeButton:@"一键收取所有阳光" color:[UIColor systemOrangeColor] action:@selector(collectAllButtonTapped)];
    [controlView addSubview:self.collectAllButton];
    
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:self.statusLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [controlView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [controlView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [controlView.heightAnchor constraintEqualToConstant:256],
        
        [baseLabel.topAnchor constraintEqualToAnchor:controlView.topAnchor constant:8],
        [baseLabel.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [baseLabel.heightAnchor constraintEqualToConstant:17],
        
        [self.managerBaseField.topAnchor constraintEqualToAnchor:baseLabel.bottomAnchor constant:4],
        [self.managerBaseField.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.managerBaseField.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.managerBaseField.heightAnchor constraintEqualToConstant:34],
        
        [funcLabel.topAnchor constraintEqualToAnchor:self.managerBaseField.bottomAnchor constant:8],
        [funcLabel.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [funcLabel.heightAnchor constraintEqualToConstant:17],
        
        [self.collectFunctionField.topAnchor constraintEqualToAnchor:funcLabel.bottomAnchor constant:4],
        [self.collectFunctionField.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.collectFunctionField.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.collectFunctionField.heightAnchor constraintEqualToConstant:34],
        
        [self.scanButton.topAnchor constraintEqualToAnchor:self.collectFunctionField.bottomAnchor constant:10],
        [self.scanButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.scanButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.scanButton.heightAnchor constraintEqualToConstant:38],
        
        [self.quickValidateButton.topAnchor constraintEqualToAnchor:self.scanButton.bottomAnchor constant:8],
        [self.quickValidateButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.quickValidateButton.trailingAnchor constraintEqualToAnchor:controlView.centerXAnchor constant:-4],
        [self.quickValidateButton.heightAnchor constraintEqualToConstant:36],
        
        [self.collectAllButton.topAnchor constraintEqualToAnchor:self.scanButton.bottomAnchor constant:8],
        [self.collectAllButton.leadingAnchor constraintEqualToAnchor:controlView.centerXAnchor constant:4],
        [self.collectAllButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.collectAllButton.heightAnchor constraintEqualToConstant:36],
        
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.collectAllButton.bottomAnchor constant:6],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.statusLabel.heightAnchor constraintEqualToConstant:18]
    ]];
    
    // 调用日志：每次调用用了什么函数、什么参数、返回什么，都留在这里
    self.logTextView = [[UITextView alloc] init];
    self.logTextView.font = [AppTheme monospaceFont:10];
    self.logTextView.textColor = IMGUI_TEXT_DISABLED;
    self.logTextView.backgroundColor = [UIColor colorWithWhite:0.08f alpha:1.0f];
    self.logTextView.layer.borderWidth = 1;
    self.logTextView.layer.borderColor = [UIColor colorWithWhite:0.25f alpha:1.0f].CGColor;
    self.logTextView.editable = NO;
    self.logTextView.text = @"调用日志：\n";
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logTextView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.logTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.logTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [self.logTextView.heightAnchor constraintEqualToConstant:92]
    ]];
    
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = IMGUI_BG_COLOR;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:[SunObjectCell class] forCellReuseIdentifier:@"SunObjectCell"];
    [self.view addSubview:self.tableView];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:controlView.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.logTextView.topAnchor constant:-4]
    ]];
}

- (UILabel *)makeCaption:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = IMGUI_TEXT;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UITextField *)makeField:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [AppTheme monospaceFont:14];
    field.keyboardType = UIKeyboardTypeASCIICapable;
    field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
    field.textColor = IMGUI_TEXT;
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (UIButton *)makeButton:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.backgroundColor = color;
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 4;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

#pragma mark - 日志

- (void)appendLog:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray<NSString *> *lines = [[self.logTextView.text componentsSeparatedByString:@"\n"] mutableCopy];
        if (lines.count == 0) [lines addObject:@"调用日志："];
        [lines addObject:line];
        while (lines.count > 10) [lines removeObjectAtIndex:1];
        self.logTextView.text = [lines componentsJoinedByString:@"\n"];
        [self.logTextView scrollRangeToVisible:NSMakeRange(self.logTextView.text.length, 0)];
    });
}

#pragma mark - 动作

- (void)backTapped {
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)scanButtonTapped {
    uint64_t managerBase = SunParseAddress(self.managerBaseField.text);
    if (managerBase == 0) {
        [self showAlert:@"错误" message:@"请输入阳光管理器基址"];
        return;
    }
    
    [self.sunObjects removeAllObjects];
    [self.tableView reloadData];
    
    self.statusLabel.text = @"正在扫描...";
    self.scanButton.enabled = NO;
    [self appendLog:[NSString stringWithFormat:@"扫描 管理器基址=0x%llX", managerBase]];
    
    [[SunScanner sharedInstance] scanSunObjectsWithManagerBase:managerBase completion:^(NSArray *sunObjects, NSError *error) {
        self.scanButton.enabled = YES;
        
        if (error) {
            self.statusLabel.text = [NSString stringWithFormat:@"扫描失败: %@", error.localizedDescription];
            [self showAlert:@"扫描失败" message:error.localizedDescription];
        } else {
            [self.sunObjects addObjectsFromArray:sunObjects];
            [self.tableView reloadData];
            self.statusLabel.text = [NSString stringWithFormat:@"找到 %lu 个阳光对象", (unsigned long)sunObjects.count];
            [self appendLog:[NSString stringWithFormat:@"扫描完成：%lu 个对象", (unsigned long)sunObjects.count]];
        }
    }];
}

- (void)quickValidateButtonTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"快速验证阳光对象"
                                                                   message:@"输入可能的阳光对象地址\n(从寄存器X22获取，例如: 0x280F75720)"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"0x280F75720";
        textField.keyboardType = UIKeyboardTypeASCIICapable;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        uint64_t testAddr = SunParseAddress(alert.textFields.firstObject.text);
        if (testAddr == 0) {
            [self showAlert:@"错误" message:@"无效的地址"];
            return;
        }
        
        uint64_t managerBase = SunParseAddress(self.managerBaseField.text);
        uint64_t possibleObject = testAddr - 0x08;
        
        int sunType = 0;
        BOOL isValid = [[SunScanner sharedInstance] validateSunObject:possibleObject
                                                          managerBase:managerBase
                                                               sunType:&sunType];
        
        [self appendLog:[NSString stringWithFormat:@"验证 X22=0x%llX → 对象=0x%llX 管理器=0x%llX → %@",
                         testAddr, possibleObject, managerBase, isValid ? @"通过" : @"失败"]];
        
        if (isValid) {
            [self.sunObjects removeAllObjects];
            [self.sunObjects addObject:@{
                @"address": @(possibleObject),
                @"type": @(sunType),
                @"managerBase": @(managerBase)
            }];
            [self.tableView reloadData];
            self.statusLabel.text = [NSString stringWithFormat:@"验证成功: 0x%llX - %@", possibleObject, SunTypeName(sunType)];
        } else {
            self.statusLabel.text = @"验证失败: 不是有效的阳光对象";
            [self showAlert:@"验证失败" message:@"该地址不是有效的阳光对象\n请检查地址和阳光管理器基址是否正确"];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)collectAllButtonTapped {
    if (self.sunObjects.count == 0) {
        [self showAlert:@"提示" message:@"没有可收取的阳光对象"];
        return;
    }
    
    uint64_t func = SunParseAddress(self.collectFunctionField.text);
    if (func == 0) {
        [self showAlert:@"提示" message:@"请先填写收取函数地址"];
        return;
    }
    self.collectSunFunction = func;
    [self performCollectAll];
}

- (void)performCollectAll {
    if (self.collectSunFunction == 0) return;
    
    self.statusLabel.text = @"正在收取阳光...";
    self.collectAllButton.enabled = NO;
    
    uint64_t fn = self.collectSunFunction;
    [self appendLog:[NSString stringWithFormat:@"收取开始 fn=0x%llX，共 %lu 个对象", fn, (unsigned long)self.sunObjects.count]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSUInteger successCount = 0;
        NSUInteger failCount = 0;
        
        for (NSDictionary *sunInfo in self.sunObjects) {
            uint64_t sunObject = [sunInfo[@"address"] unsignedLongLongValue];
            
            NSError *error = nil;
            uint64_t result = [[RemoteCallEngine sharedInstance] callFunctionAtAddress:fn
                                                                             parameters:@[@(sunObject)]
                                                                            paramCount:1
                                                                                  error:&error];
            
            if (error) {
                failCount++;
                [self appendLog:[NSString stringWithFormat:@"失败 fn=0x%llX X0=0x%llX : %@",
                                 fn, sunObject, error.localizedDescription]];
            } else {
                successCount++;
                [self appendLog:[NSString stringWithFormat:@"成功 fn=0x%llX X0=0x%llX → 0x%llX",
                                 fn, sunObject, result]];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.collectAllButton.enabled = YES;
            self.statusLabel.text = [NSString stringWithFormat:@"收取完成: 成功 %lu, 失败 %lu",
                                     (unsigned long)successCount, (unsigned long)failCount];
        });
    });
}

- (void)collectSunObject:(uint64_t)sunObject {
    uint64_t fn = SunParseAddress(self.collectFunctionField.text);
    if (fn == 0) {
        [self showAlert:@"提示" message:@"请先填写收取函数地址"];
        return;
    }
    self.collectSunFunction = fn;
    
    self.statusLabel.text = @"正在收取...";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        uint64_t result = [[RemoteCallEngine sharedInstance] callFunctionAtAddress:fn
                                                                         parameters:@[@(sunObject)]
                                                                        paramCount:1
                                                                              error:&error];
        
        if (error) {
            [self appendLog:[NSString stringWithFormat:@"失败 fn=0x%llX X0=0x%llX : %@",
                             fn, sunObject, error.localizedDescription]];
        } else {
            [self appendLog:[NSString stringWithFormat:@"成功 fn=0x%llX X0=0x%llX → 0x%llX",
                             fn, sunObject, result]];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self.statusLabel.text = [NSString stringWithFormat:@"收取失败: %@", error.localizedDescription];
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"收取成功，返回值: 0x%llX", result];
            }
        });
    });
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sunObjects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SunObjectCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SunObjectCell" forIndexPath:indexPath];
    
    if (indexPath.row < self.sunObjects.count) {
        NSDictionary *sunInfo = self.sunObjects[indexPath.row];
        uint64_t address = [sunInfo[@"address"] unsignedLongLongValue];
        uint64_t managerBase = [sunInfo[@"managerBase"] unsignedLongLongValue];
        int type = [sunInfo[@"type"] intValue];
        
        cell.addressLabel.text = [NSString stringWithFormat:@"0x%llX", address];
        cell.typeLabel.text = SunTypeName(type);
        cell.fieldLabel.text = [NSString stringWithFormat:@"类型@0x74=%d   管理器@0x08=0x%llX", type, managerBase];
        cell.paramLabel.text = [NSString stringWithFormat:@"调用参数 X0 = 0x%llX", address];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.sunObjects.count) return;
    
    NSDictionary *sunInfo = self.sunObjects[indexPath.row];
    uint64_t address = [sunInfo[@"address"] unsignedLongLongValue];
    uint64_t managerBase = [sunInfo[@"managerBase"] unsignedLongLongValue];
    int type = [sunInfo[@"type"] intValue];
    uint64_t fn = SunParseAddress(self.collectFunctionField.text);
    
    // 详情里把这一行涉及的每个参数都列出来
    NSString *detail = [NSString stringWithFormat:
        @"对象地址: 0x%llX\n类型@0x74: %d (%@)\n管理器@0x08: 0x%llX\n收取函数: %@\n调用参数: X0 = 0x%llX",
        address, type, SunTypeName(type), managerBase,
        fn ? [NSString stringWithFormat:@"0x%llX", fn] : @"(未填写)",
        address];
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"对象参数"
                                                                   message:detail
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"收取这个阳光" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self collectSunObject:address];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制地址" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"0x%llX", address];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制调用参数 (X0)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"0x%llX", address];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - 通用

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end