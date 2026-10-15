#import "UI/Pages/MorePage.h"
#import "UI/Pages/PointerScanPage.h"
#import "UI/Pages/SettingsPage.h"
#import "UI/Pages/SunScanPage.h"
#import "UI/Pages/RemoteCallPage.h"
#import "UI/Pages/ModulePage.h"
#import "UI/Pages/OffsetCalcPage.h"
#import "Services/LogService.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Components/ThemeConfig.h"

@interface MorePage ()

@end

@implementation MorePage

- (UIButton *)createCyberButtonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 2;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    self.dataSource = @[@"指针扫描", @"对PVZ调用", @"远程调用", @"模块查看", @"偏移计算", @"设置"];
    
    // 添加标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"更多";
    titleLabel.textColor = IMGUI_TEXT;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];
    
    // 添加返回按钮
    UIButton *backButton = [self createCyberButtonWithTitle:@"返回" color:IMGUI_BUTTON action:@selector(backButtonTapped)];
    [self.view addSubview:backButton];
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    self.tableView.tableFooterView = [[UIView alloc] init]; // 隐藏多余的分割线
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        // 标题和按钮约束
        [titleLabel.centerYAnchor constraintEqualToAnchor:backButton.centerYAnchor],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [backButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [backButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [backButton.widthAnchor constraintEqualToConstant:60],
        [backButton.heightAnchor constraintEqualToConstant:28],
        
        // TableView 约束
        [self.tableView.topAnchor constraintEqualToAnchor:backButton.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"MoreCell"];
}

- (void)backButtonTapped {
    [[FloatingWindow sharedInstance] hide];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MoreCell" forIndexPath:indexPath];
    
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.text = self.dataSource[indexPath.row];
    cell.textLabel.textColor = IMGUI_TEXT;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *option = self.dataSource[indexPath.row];
    [LoggingService log:@"点击了更多选项: %@", option];
    
    UIViewController *vc = nil;
    if ([option isEqualToString:@"指针扫描"]) {
        vc = [[PointerScanPage alloc] init];
    } else if ([option isEqualToString:@"对PVZ调用"]) {
        SunScannerPage *sunVC = [[SunScannerPage alloc] init];
        sunVC.sunManagerBase = 0;
        vc = sunVC;
    } else if ([option isEqualToString:@"远程调用"]) {
        vc = [[RemoteCallPage alloc] init];
    } else if ([option isEqualToString:@"模块查看"]) {
        vc = [[ModulePage alloc] init];
    } else if ([option isEqualToString:@"偏移计算"]) {
        vc = [[OffsetCalcPage alloc] init];
    } else if ([option isEqualToString:@"设置"]) {
        vc = [[SettingsPage alloc] init];
    }
    
    if (vc) {
        [self addChildViewController:vc];
        [self.view addSubview:vc.view];
        
        vc.view.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [vc.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [vc.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [vc.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [vc.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
        
        [vc didMoveToParentViewController:self];
    }
}

@end
