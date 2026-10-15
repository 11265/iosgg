#import "UI/Pages/AccessPage.h"
#import "UI/Components/ThemeConfig.h"
#import "Services/LogService.h"
#import "Services/Debugger/SSDebugger.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Pages/MemoryPage.h"
#import "Models/AccessRecord.h"
#import "UI/Pages/AccessDetailViewController.h"

#import "UI/Components/AccessCell.h"
#import "UI/Components/CyberButton.h"
#import "UI/Components/TerminalInputField.h"
#import "Models/AccessViewModel.h"

@interface AccessPage () <UITableViewDelegate, UITableViewDataSource, AccessCellDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) AccessViewModel *viewModel;

@property (nonatomic, strong) CyberButton *toggleDebugButton;
@property (nonatomic, strong) CyberButton *clearButton;
@property (nonatomic, strong) CyberButton *closeButton;

@property (nonatomic, strong) UILabel *statusLabel;

@end

@implementation AccessPage

- (instancetype)init {
    if (self = [super init]) {
        _viewModel = [[AccessViewModel alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [AppTheme backgroundColor];
    
    [self setupControlPanel];
    [self setupTableView];
    [self setupNotifications];
}

- (void)setupControlPanel {
    UIView *controlPanel = [[UIView alloc] init];
    controlPanel.backgroundColor = [AppTheme childBackgroundColor];
    controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controlPanel];
    
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"已停止";
    self.statusLabel.font = [AppTheme regularFont:12];
    self.statusLabel.textColor = [AppTheme errorColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.statusLabel];
    
    self.toggleDebugButton = [CyberButton buttonWithTitle:@"启动调试" style:CyberButtonStyleDefault];
    [self.toggleDebugButton addTarget:self action:@selector(toggleDebugTapped) forControlEvents:UIControlEventTouchUpInside];
    [controlPanel addSubview:self.toggleDebugButton];
    
    self.clearButton = [CyberButton buttonWithTitle:@"清除全部" style:CyberButtonStyleDanger];
    [self.clearButton addTarget:self action:@selector(clearButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [controlPanel addSubview:self.clearButton];
    
    self.closeButton = [CyberButton buttonWithTitle:@"关闭" style:CyberButtonStyleDefault];
    [self.closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [controlPanel addSubview:self.closeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [controlPanel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:5],
        [controlPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [controlPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [controlPanel.heightAnchor constraintEqualToConstant:40],
        
        [self.toggleDebugButton.topAnchor constraintEqualToAnchor:controlPanel.topAnchor constant:5],
        [self.toggleDebugButton.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor],
        [self.toggleDebugButton.widthAnchor constraintEqualToConstant:100],
        [self.toggleDebugButton.heightAnchor constraintEqualToConstant:22],
        
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.toggleDebugButton.trailingAnchor constant:10],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.toggleDebugButton.centerYAnchor],
        
        [self.clearButton.topAnchor constraintEqualToAnchor:controlPanel.topAnchor constant:5],
        [self.clearButton.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-5],
        [self.clearButton.widthAnchor constraintEqualToConstant:80],
        [self.clearButton.heightAnchor constraintEqualToConstant:22],
        
        [self.closeButton.topAnchor constraintEqualToAnchor:controlPanel.topAnchor constant:5],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:controlPanel.trailingAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:50],
        [self.closeButton.heightAnchor constraintEqualToConstant:22]
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [AppTheme childBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.tableView.rowHeight = 80;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[AccessCell class] forCellReuseIdentifier:[AccessCell reuseIdentifier]];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.layer.borderColor = [AppTheme borderColor].CGColor;
    self.tableView.layer.borderWidth = [AppTheme borderWidth];
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:53],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8]
    ]];
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleViewModelUpdate:)
                                                 name:AccessViewModelDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDebugStateChanged:)
                                                 name:AccessViewModelDebugStateChangedNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notification Handlers

- (void)handleViewModelUpdate:(NSNotification *)notification {
    [LoggingService log:@"AccessPage: 收到更新通知，记录数=%lu", (unsigned long)self.viewModel.watchpointCount];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)handleDebugStateChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateButtonStates];
    });
}

#pragma mark - Button Actions

- (void)toggleDebugTapped {
    [self.viewModel toggleDebugging];
}

- (void)clearButtonTapped {
    [self.viewModel removeAllWatchpoints];
}

- (void)closeButtonTapped {
    [[FloatingWindow sharedInstance] hide];
}

- (void)updateButtonStates {
    if (self.viewModel.isDebugging) {
        [self.toggleDebugButton setTitle:@"停止调试" forState:UIControlStateNormal];
        self.toggleDebugButton.style = CyberButtonStyleDanger;
        self.statusLabel.text = @"运行中";
        self.statusLabel.textColor = [UIColor colorWithRed:0.2f green:0.8f blue:0.4f alpha:1.0f];
    } else {
        [self.toggleDebugButton setTitle:@"启动调试" forState:UIControlStateNormal];
        self.toggleDebugButton.style = CyberButtonStyleDefault;
        self.statusLabel.text = @"已停止";
        self.statusLabel.textColor = [AppTheme errorColor];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.viewModel.watchpointCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AccessCell *cell = [tableView dequeueReusableCellWithIdentifier:[AccessCell reuseIdentifier] forIndexPath:indexPath];
    cell.delegate = self;
    AccessRecord *record = [self.viewModel recordAtIndex:indexPath.row];
    if (record) {
        [cell configureWithRecord:record];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    AccessRecord *record = [self.viewModel recordAtIndex:indexPath.row];
    if (!record) return;
    
    AccessDetailsViewController *detailVC = [[AccessDetailsViewController alloc] init];
    detailVC.record = record;
    detailVC.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:detailVC animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.viewModel removeWatchpointAtIndex:indexPath.row];
    }
}

#pragma mark - AccessCellDelegate

- (void)accessCellDidChangeEnabled:(BOOL)enabled forAddress:(uint64_t)address {
    [self.viewModel setEnabled:enabled forAddress:address];
}

- (void)accessCellDidChangeType:(NSInteger)type forAddress:(uint64_t)address {
    SSBreakpointType bpType = SSBreakpointTypeWrite;
    if (type == 1) {
        bpType = SSBreakpointTypeRead;
    } else if (type == 2) {
        bpType = SSBreakpointTypeReadWrite;
    }
    [self.viewModel setType:bpType forAddress:address];
}

@end
