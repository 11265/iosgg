#import "UI/Pages/System/ModulePage.h"
#import "Modules/ProcessInfo/ModuleViewer.h"
#import "Services/LogService.h"
#import "UI/Components/ThemeConfig.h"

@interface ModulePage () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>

@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSMutableArray<ModuleInfo *> *allModules;
@property (nonatomic, strong) NSMutableArray<ModuleInfo *> *filteredModules;
@property (nonatomic, strong) UIButton *refreshButton;
@property (nonatomic, strong) UIButton *baseCopyBtn;
@property (nonatomic, strong) UIButton *backButton;

@end

@implementation ModulePage

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"模块查看器";
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    self.allModules = [NSMutableArray array];
    self.filteredModules = [NSMutableArray array];
    
    [self setupUI];
    [self loadModules];
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
    titleLabel.text = @"模块查看器";
    titleLabel.textColor = IMGUI_TEXT;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:titleLabel];
    
    self.refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.refreshButton setTitle:@"刷新" forState:UIControlStateNormal];
    [self.refreshButton setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    self.refreshButton.backgroundColor = IMGUI_BUTTON;
    self.refreshButton.layer.cornerRadius = 2;
    self.refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.refreshButton addTarget:self action:@selector(refreshButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:self.refreshButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:44],
        
        [self.backButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10],
        [self.backButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.backButton.widthAnchor constraintEqualToConstant:60],
        
        [titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        
        [self.refreshButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [self.refreshButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.refreshButton.widthAnchor constraintEqualToConstant:60],
        [self.refreshButton.heightAnchor constraintEqualToConstant:28]
    ]];
    
    UIView *searchView = [[UIView alloc] init];
    searchView.backgroundColor = IMGUI_BG_COLOR;
    searchView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:searchView];
    
    self.searchField = [[UITextField alloc] init];
    self.searchField.placeholder = @"输入模块名称或地址搜索...";
    self.searchField.borderStyle = UITextBorderStyleRoundedRect;
    self.searchField.font = [UIFont fontWithName:@"Menlo" size:13];
    self.searchField.backgroundColor = IMGUI_FRAME_BG;
    self.searchField.textColor = IMGUI_TEXT;
    self.searchField.delegate = self;
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchField addTarget:self action:@selector(searchTextChanged) forControlEvents:UIControlEventEditingChanged];
    [searchView addSubview:self.searchField];
    
    self.baseCopyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.baseCopyBtn setTitle:@"复制基址" forState:UIControlStateNormal];
    [self.baseCopyBtn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    self.baseCopyBtn.backgroundColor = [UIColor systemGreenColor];
    self.baseCopyBtn.layer.cornerRadius = 2;
    self.baseCopyBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    self.baseCopyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.baseCopyBtn addTarget:self action:@selector(copyBaseButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [searchView addSubview:self.baseCopyBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [searchView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:5],
        [searchView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [searchView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [searchView.heightAnchor constraintEqualToConstant:40],
        
        [self.searchField.leadingAnchor constraintEqualToAnchor:searchView.leadingAnchor constant:10],
        [self.searchField.trailingAnchor constraintEqualToAnchor:self.baseCopyBtn.leadingAnchor constant:-5],
        [self.searchField.centerYAnchor constraintEqualToAnchor:searchView.centerYAnchor],
        [self.searchField.heightAnchor constraintEqualToConstant:32],
        
        [self.baseCopyBtn.trailingAnchor constraintEqualToAnchor:searchView.trailingAnchor constant:-10],
        [self.baseCopyBtn.centerYAnchor constraintEqualToAnchor:searchView.centerYAnchor],
        [self.baseCopyBtn.widthAnchor constraintEqualToConstant:70],
        [self.baseCopyBtn.heightAnchor constraintEqualToConstant:32]
    ]];
    
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:searchView.bottomAnchor constant:5],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.statusLabel.heightAnchor constraintEqualToConstant:20]
    ]];
    
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = IMGUI_BG_COLOR;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ModuleCell"];
    [self.view addSubview:self.tableView];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:5],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)loadModules {
    self.statusLabel.text = @"正在加载模块...";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<ModuleInfo *> *modules = [[ModuleViewer sharedInstance] getAllModules];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.allModules removeAllObjects];
            [self.allModules addObjectsFromArray:modules];
            [self filterModules];
            self.statusLabel.text = [NSString stringWithFormat:@"共 %lu 个模块", (unsigned long)self.allModules.count];
        });
    });
}

- (void)filterModules {
    NSString *searchText = self.searchField.text;
    
    [self.filteredModules removeAllObjects];
    
    if (searchText.length == 0) {
        [self.filteredModules addObjectsFromArray:self.allModules];
    } else {
        for (ModuleInfo *module in self.allModules) {
            if ([module.name.lowercaseString containsString:searchText.lowercaseString] ||
                [module.path.lowercaseString containsString:searchText.lowercaseString] ||
                [searchText hasPrefix:@"0x"] || [searchText hasPrefix:@"0X"]) {
                
                uint64_t searchAddr = 0;
                NSScanner *scanner = [NSScanner scannerWithString:searchText];
                [scanner scanHexLongLong:&searchAddr];
                
                if (searchAddr >= module.baseAddress && searchAddr < module.endAddress) {
                    if (![self.filteredModules containsObject:module]) {
                        [self.filteredModules addObject:module];
                    }
                }
            }
        }
        
        if (self.filteredModules.count == 0) {
            for (ModuleInfo *module in self.allModules) {
                if ([module.name.lowercaseString containsString:searchText.lowercaseString] ||
                    [module.path.lowercaseString containsString:searchText.lowercaseString]) {
                    [self.filteredModules addObject:module];
                }
            }
        }
    }
    
    [self.tableView reloadData];
}

- (void)backTapped {
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)refreshButtonTapped {
    self.refreshButton.enabled = NO;
    [self loadModules];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.refreshButton.enabled = YES;
    });
}

- (void)searchTextChanged {
    [self filterModules];
}

- (void)copyBaseButtonTapped {
    if (self.filteredModules.count == 0) {
        [self showAlert:@"提示" message:@"没有可复制的模块"];
        return;
    }
    
    if (self.filteredModules.count == 1) {
        ModuleInfo *module = self.filteredModules[0];
        NSString *baseStr = [NSString stringWithFormat:@"0x%llX", module.baseAddress];
        [UIPasteboard generalPasteboard].string = baseStr;
        [self showAlert:@"已复制" message:[NSString stringWithFormat:@"%@ 的基址: %@", module.name, baseStr]];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择要复制的模块"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        
        for (ModuleInfo *module in self.filteredModules) {
            NSString *title = [NSString stringWithFormat:@"%@ - 0x%llX", module.name, module.baseAddress];
            [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *baseStr = [NSString stringWithFormat:@"0x%llX", module.baseAddress];
                [UIPasteboard generalPasteboard].string = baseStr;
            }]];
        }
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredModules.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModuleCell" forIndexPath:indexPath];
    
    if (indexPath.row < self.filteredModules.count) {
        ModuleInfo *module = self.filteredModules[indexPath.row];
        
        cell.backgroundColor = IMGUI_BG_COLOR;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        NSString *nameStr = module.name;
        NSString *baseStr = [NSString stringWithFormat:@"0x%llX", module.baseAddress];
        NSString *sizeStr = [NSString stringWithFormat:@"0x%llX (%.2f MB)", module.size, (double)module.size / (1024.0 * 1024.0)];
        NSString *detailStr = [NSString stringWithFormat:@"%@ | %@", baseStr, sizeStr];
        
        cell.textLabel.text = nameStr;
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:13];
        cell.textLabel.textColor = IMGUI_TEXT;
        
        cell.detailTextLabel.text = detailStr;
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:11];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row < self.filteredModules.count) {
        ModuleInfo *module = self.filteredModules[indexPath.row];
        
        NSString *info = [NSString stringWithFormat:@"名称: %@\n基址: 0x%llX\n大小: 0x%llX (%.2f MB)\n路径: %@",
                          module.name, module.baseAddress, module.size, (double)module.size / (1024.0 * 1024.0), module.path];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:module.name
                                                                       message:info
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"复制基址" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *baseStr = [NSString stringWithFormat:@"0x%llX", module.baseAddress];
            [UIPasteboard generalPasteboard].string = baseStr;
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [UIPasteboard generalPasteboard].string = module.path;
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
