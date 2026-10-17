#import "UI/Pages/Scanner/SunScanPage.h"
#import "Modules/Scanner/SunScanner.h"
#import "Services/LogService.h"
#import "Modules/Remote/RemoteCallEngine.h"
#import "UI/Components/ThemeConfig.h"

@interface SunScannerPage () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITextField *managerBaseField;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *quickValidateButton;
@property (nonatomic, strong) UIButton *collectAllButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
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
    
    UILabel *baseLabel = [[UILabel alloc] init];
    baseLabel.text = @"阳光管理器基址";
    baseLabel.font = [UIFont systemFontOfSize:14];
    baseLabel.textColor = IMGUI_TEXT;
    baseLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView addSubview:baseLabel];
    
    self.managerBaseField = [[UITextField alloc] init];
    self.managerBaseField.placeholder = @"例如: 0x130138000";
    self.managerBaseField.borderStyle = UITextBorderStyleRoundedRect;
    self.managerBaseField.font = [UIFont fontWithName:@"Menlo" size:14];
    self.managerBaseField.keyboardType = UIKeyboardTypeASCIICapable;
    self.managerBaseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.managerBaseField.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
    self.managerBaseField.textColor = IMGUI_TEXT;
    if (self.sunManagerBase != 0) {
        self.managerBaseField.text = [NSString stringWithFormat:@"0x%llX", self.sunManagerBase];
    }
    [controlView addSubview:self.managerBaseField];
    self.managerBaseField.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.scanButton setTitle:@"扫描阳光对象" forState:UIControlStateNormal];
    self.scanButton.backgroundColor = [UIColor systemBlueColor];
    [self.scanButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.scanButton.layer.cornerRadius = 4;
    self.scanButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.scanButton addTarget:self action:@selector(scanButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [controlView addSubview:self.scanButton];
    self.scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.quickValidateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.quickValidateButton setTitle:@"快速验证已知地址" forState:UIControlStateNormal];
    self.quickValidateButton.backgroundColor = [UIColor systemPurpleColor];
    [self.quickValidateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.quickValidateButton.layer.cornerRadius = 4;
    self.quickValidateButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.quickValidateButton addTarget:self action:@selector(quickValidateButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [controlView addSubview:self.quickValidateButton];
    self.quickValidateButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.collectAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.collectAllButton setTitle:@"一键收取所有阳光" forState:UIControlStateNormal];
    self.collectAllButton.backgroundColor = [UIColor systemOrangeColor];
    [self.collectAllButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.collectAllButton.layer.cornerRadius = 4;
    self.collectAllButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.collectAllButton addTarget:self action:@selector(collectAllButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [controlView addSubview:self.collectAllButton];
    self.collectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [controlView addSubview:self.statusLabel];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [controlView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [controlView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [controlView.heightAnchor constraintEqualToConstant:230],
        
        [baseLabel.topAnchor constraintEqualToAnchor:controlView.topAnchor constant:10],
        [baseLabel.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        
        [self.managerBaseField.topAnchor constraintEqualToAnchor:baseLabel.bottomAnchor constant:8],
        [self.managerBaseField.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.managerBaseField.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.managerBaseField.heightAnchor constraintEqualToConstant:36],
        
        [self.scanButton.topAnchor constraintEqualToAnchor:self.managerBaseField.bottomAnchor constant:12],
        [self.scanButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.scanButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.scanButton.heightAnchor constraintEqualToConstant:40],
        
        [self.quickValidateButton.topAnchor constraintEqualToAnchor:self.scanButton.bottomAnchor constant:8],
        [self.quickValidateButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.quickValidateButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.quickValidateButton.heightAnchor constraintEqualToConstant:40],
        
        [self.collectAllButton.topAnchor constraintEqualToAnchor:self.quickValidateButton.bottomAnchor constant:8],
        [self.collectAllButton.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.collectAllButton.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
        [self.collectAllButton.heightAnchor constraintEqualToConstant:40],
        
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.collectAllButton.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:controlView.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:controlView.trailingAnchor constant:-16],
    ]];
    
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = IMGUI_BG_COLOR;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:self.tableView];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:controlView.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)backTapped {
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)scanButtonTapped {
    NSString *baseStr = [self.managerBaseField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if (baseStr.length == 0) {
        [self showAlert:@"错误" message:@"请输入阳光管理器基址"];
        return;
    }
    
    uint64_t managerBase = 0;
    if ([baseStr hasPrefix:@"0x"] || [baseStr hasPrefix:@"0X"]) {
        NSString *hexStr = [baseStr substringFromIndex:2];
        NSScanner *scanner = [NSScanner scannerWithString:hexStr];
        [scanner scanHexLongLong:&managerBase];
    } else {
        managerBase = [baseStr longLongValue];
    }
    
    if (managerBase == 0) {
        [self showAlert:@"错误" message:@"无效的地址格式"];
        return;
    }
    
    [self.sunObjects removeAllObjects];
    [self.tableView reloadData];
    
    self.statusLabel.text = @"正在扫描...";
    self.scanButton.enabled = NO;
    
    [[SunScanner sharedInstance] scanSunObjectsWithManagerBase:managerBase completion:^(NSArray *sunObjects, NSError *error) {
        self.scanButton.enabled = YES;
        
        if (error) {
            self.statusLabel.text = [NSString stringWithFormat:@"扫描失败: %@", error.localizedDescription];
            [self showAlert:@"扫描失败" message:error.localizedDescription];
        } else {
            [self.sunObjects addObjectsFromArray:sunObjects];
            [self.tableView reloadData];
            self.statusLabel.text = [NSString stringWithFormat:@"找到 %lu 个阳光对象", (unsigned long)sunObjects.count];
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
        NSString *addrStr = alert.textFields.firstObject.text;
        uint64_t testAddr = 0;
        
        if ([addrStr hasPrefix:@"0x"] || [addrStr hasPrefix:@"0X"]) {
            NSString *hexStr = [addrStr substringFromIndex:2];
            NSScanner *scanner = [NSScanner scannerWithString:hexStr];
            [scanner scanHexLongLong:&testAddr];
        } else {
            testAddr = [addrStr longLongValue];
        }
        
        if (testAddr == 0) {
            [self showAlert:@"错误" message:@"无效的地址"];
            return;
        }
        
        NSString *baseStr = [self.managerBaseField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        uint64_t managerBase = 0;
        
        if ([baseStr hasPrefix:@"0x"] || [baseStr hasPrefix:@"0X"]) {
            NSString *hexStr = [baseStr substringFromIndex:2];
            NSScanner *scanner = [NSScanner scannerWithString:hexStr];
            [scanner scanHexLongLong:&managerBase];
        } else {
            managerBase = [baseStr longLongValue];
        }
        
        uint64_t possibleObject = testAddr - 0x08;
        [LoggingService log:@"[快速验证] 测试地址: 0x%llX", testAddr];
        [LoggingService log:@"[快速验证] 可能的阳光对象: 0x%llX", possibleObject];
        [LoggingService log:@"[快速验证] 阳光管理器基址: 0x%llX", managerBase];
        
        int sunType = 0;
        BOOL isValid = [[SunScanner sharedInstance] validateSunObject:possibleObject
                                                          managerBase:managerBase
                                                               sunType:&sunType];
        
        if (isValid) {
            [self.sunObjects removeAllObjects];
            NSDictionary *sunInfo = @{
                @"address": @(possibleObject),
                @"type": @(sunType),
                @"managerBase": @(managerBase)
            };
            [self.sunObjects addObject:sunInfo];
            [self.tableView reloadData];
            
            NSString *typeStr = @"";
            switch (sunType) {
                case 4: typeStr = @"普通(25)"; break;
                case 5: typeStr = @"特殊(15)"; break;
                case 6: typeStr = @"未知"; break;
                default: typeStr = [NSString stringWithFormat:@"类型%d", sunType]; break;
            }
            
            self.statusLabel.text = [NSString stringWithFormat:@"验证成功: 0x%llX - %@", possibleObject, typeStr];
            [self showAlert:@"验证成功" message:[NSString stringWithFormat:@"找到阳光对象: 0x%llX\n类型: %@", possibleObject, typeStr]];
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
    
    if (self.collectSunFunction == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入收取函数地址"
                                                                       message:@"请输入收取阳光函数地址\n(例如: 0x1008FD608)"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"0x1008FD608";
            textField.keyboardType = UIKeyboardTypeASCIICapable;
        }];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *funcStr = alert.textFields.firstObject.text;
            uint64_t funcAddr = 0;
            
            if ([funcStr hasPrefix:@"0x"] || [funcStr hasPrefix:@"0X"]) {
                NSString *hexStr = [funcStr substringFromIndex:2];
                NSScanner *scanner = [NSScanner scannerWithString:hexStr];
                [scanner scanHexLongLong:&funcAddr];
            } else {
                funcAddr = [funcStr longLongValue];
            }
            
            if (funcAddr != 0) {
                self.collectSunFunction = funcAddr;
                [self performCollectAll];
            } else {
                [self showAlert:@"错误" message:@"无效的函数地址"];
            }
        }]];
        
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self performCollectAll];
    }
}

- (void)performCollectAll {
    if (self.collectSunFunction == 0) {
        return;
    }
    
    self.statusLabel.text = @"正在收取阳光...";
    self.collectAllButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSUInteger successCount = 0;
        NSUInteger failCount = 0;
        
        for (NSDictionary *sunInfo in self.sunObjects) {
            uint64_t sunObject = [sunInfo[@"address"] unsignedLongLongValue];
            
            NSError *error = nil;
            uint64_t result = [[RemoteCallEngine sharedInstance] callFunctionAtAddress:self.collectSunFunction
                                                                             parameters:@[@(sunObject)]
                                                                            paramCount:1
                                                                                  error:&error];
            
            if (error) {
                failCount++;
                [LoggingService log:@"[阳光扫描] 收取失败: 0x%llX, 错误: %@", sunObject, error.localizedDescription];
            } else {
                successCount++;
                [LoggingService log:@"[阳光扫描] 收取成功: 0x%llX, 返回值: 0x%llX", sunObject, result];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.collectAllButton.enabled = YES;
            self.statusLabel.text = [NSString stringWithFormat:@"收取完成: 成功 %lu, 失败 %lu",
                                     (unsigned long)successCount, (unsigned long)failCount];
            
            [self.sunObjects removeAllObjects];
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sunObjects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    
    if (indexPath.row < self.sunObjects.count) {
        NSDictionary *sunInfo = self.sunObjects[indexPath.row];
        uint64_t address = [sunInfo[@"address"] unsignedLongLongValue];
        int type = [sunInfo[@"type"] intValue];
        
        NSString *typeStr = @"";
        switch (type) {
            case 4: typeStr = @"普通(25)"; break;
            case 5: typeStr = @"特殊(15)"; break;
            case 6: typeStr = @"未知"; break;
            default: typeStr = [NSString stringWithFormat:@"类型%d", type]; break;
        }
        
        cell.textLabel.text = [NSString stringWithFormat:@"0x%llX - %@", address, typeStr];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:14];
        cell.detailTextLabel.text = nil;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row < self.sunObjects.count) {
        NSDictionary *sunInfo = self.sunObjects[indexPath.row];
        uint64_t address = [sunInfo[@"address"] unsignedLongLongValue];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"操作"
                                                                       message:[NSString stringWithFormat:@"地址: 0x%llX", address]
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"收取这个阳光" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self collectSunObject:address];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"复制地址" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"0x%llX", address];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)collectSunObject:(uint64_t)sunObject {
    if (self.collectSunFunction == 0) {
        [self collectAllButtonTapped];
        return;
    }
    
    self.statusLabel.text = @"正在收取...";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        uint64_t result = [[RemoteCallEngine sharedInstance] callFunctionAtAddress:self.collectSunFunction
                                                                         parameters:@[@(sunObject)]
                                                                        paramCount:1
                                                                              error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self.statusLabel.text = [NSString stringWithFormat:@"收取失败: %@", error.localizedDescription];
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"收取成功，返回值: 0x%llX", result];
            }
        });
    });
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
