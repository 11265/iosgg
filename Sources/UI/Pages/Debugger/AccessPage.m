#import "UI/Pages/Debugger/AccessPage.h"
#import "UI/Pages/Debugger/Access/Components/AccessHeaderView.h"
#import "UI/Pages/Debugger/Access/Components/AccessCell.h"
#import "UI/Components/ThemeConfig.h"
#import "Services/LogService.h"
#import "Modules/Debugger/SSDebugger.h"
#import "UI/Components/FloatingWindow.h"
#import "UI/Pages/Memory/MemoryPage.h"
#import "Modules/Debugger/Access/AccessRecord.h"
#import "UI/Pages/Debugger/Access/AccessDetailViewController.h"
#import "UI/Pages/Debugger/AccessHitInspectorViewController.h"
#import "Modules/Debugger/Access/AccessViewModel.h"
#import "Services/SSSymbolicator.h"

@interface AccessPage () <UITableViewDelegate, UITableViewDataSource, AccessCellDelegate, AccessHeaderViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) AccessViewModel *viewModel;

@property (nonatomic, strong) AccessHeaderView *headerView;
@property (nonatomic, strong) UIView *statusBanner;
@property (nonatomic, strong) NSLayoutConstraint *bannerHeightConstraint;
@property (nonatomic, strong) UIView *emptyView;

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

    [self setupHeader];
    [self setupStatusBanner];
    [self setupTableView];
    [self setupEmptyView];
    [self setupNotifications];

    [self refreshHeader];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI

- (void)setupHeader {
    self.headerView = [[AccessHeaderView alloc] init];
    self.headerView.delegate = self;
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerView];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:48]
    ]];
}

- (void)setupStatusBanner {
    self.statusBanner = [[UIView alloc] init];
    self.statusBanner.backgroundColor = [UIColor colorWithRed:0.30f green:0.24f blue:0.04f alpha:1.0f];
    self.statusBanner.layer.cornerRadius = 6;
    self.statusBanner.clipsToBounds = YES;
    self.statusBanner.hidden = YES;
    self.statusBanner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusBanner];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"访问点未生效，点此启动调试";
    label.font = [AppTheme regularFont:11];
    label.textColor = [UIColor colorWithRed:1.0f green:0.85f blue:0.40f alpha:1.0f];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusBanner addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bannerTapped)];
    [self.statusBanner addGestureRecognizer:tap];

    self.bannerHeightConstraint = [self.statusBanner.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusBanner.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:2],
        [self.statusBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.statusBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        self.bannerHeightConstraint,

        [label.leadingAnchor constraintEqualToAnchor:self.statusBanner.leadingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:self.statusBanner.trailingAnchor constant:-10],
        [label.centerYAnchor constraintEqualToAnchor:self.statusBanner.centerYAnchor]
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.tableView.rowHeight = 96;
    self.tableView.estimatedRowHeight = 96;
    [self.tableView registerClass:[AccessCell class] forCellReuseIdentifier:[AccessCell reuseIdentifier]];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.45;
    [self.tableView addGestureRecognizer:longPress];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.statusBanner.bottomAnchor constant:6],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
}

- (void)setupEmptyView {
    self.emptyView = [[UIView alloc] init];
    self.emptyView.hidden = YES;
    self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyView];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"safari"]];
    icon.tintColor = [AppTheme textDisabledColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"还没有访问点";
    title.font = [AppTheme boldFont:16];
    title.textColor = [AppTheme textColor];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"点右上角 ＋ 输入地址，\n或到记录页选中地址后点「访问」";
    subtitle.font = [AppTheme regularFont:11];
    subtitle.textColor = [AppTheme textDisabledColor];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 2;

    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [addButton setTitle:@"添加访问点" forState:UIControlStateNormal];
    [addButton setTitleColor:[AppTheme textHighlightColor] forState:UIControlStateNormal];
    addButton.titleLabel.font = [AppTheme regularFont:13];
    addButton.layer.borderColor = [AppTheme textHighlightColor].CGColor;
    addButton.layer.borderWidth = 1;
    addButton.layer.cornerRadius = 8;
    [addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, subtitle, addButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyView.topAnchor constraintEqualToAnchor:self.tableView.topAnchor],
        [self.emptyView.leadingAnchor constraintEqualToAnchor:self.tableView.leadingAnchor],
        [self.emptyView.trailingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor],
        [self.emptyView.bottomAnchor constraintEqualToAnchor:self.tableView.bottomAnchor],

        [icon.widthAnchor constraintEqualToConstant:40],
        [icon.heightAnchor constraintEqualToConstant:40],
        [subtitle.widthAnchor constraintLessThanOrEqualToConstant:250],
        [addButton.widthAnchor constraintEqualToConstant:150],
        [addButton.heightAnchor constraintEqualToConstant:36],

        [stack.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.emptyView.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.emptyView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.emptyView.trailingAnchor constant:-16]
    ]];
}

#pragma mark - State

- (void)refreshHeader {
    NSUInteger count = self.viewModel.watchpointCount;

    [self.headerView updateWithRunning:self.viewModel.isDebugging
                             slotCount:(NSInteger)count
                             slotLimit:(NSInteger)self.viewModel.slotLimit];

    BOOL showBanner = (!self.viewModel.isDebugging && count > 0);
    self.bannerHeightConstraint.constant = showBanner ? 32 : 0;
    self.statusBanner.hidden = !showBanner;

    self.tableView.hidden = (count == 0);
    self.emptyView.hidden = (count != 0);
}

#pragma mark - Notifications

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleViewModelUpdate:)
                                                 name:AccessViewModelDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDebugStateChanged:)
                                                 name:AccessViewModelDebugStateChangedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSymbolsReady:)
                                                 name:SSSymbolicatorObjCMethodsDidBecomeReadyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRecordUpdate:)
                                                 name:kAccessRecordDidUpdateNotification
                                               object:nil];
}

- (void)handleViewModelUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshHeader];
        [self.tableView reloadData];
    });
}

- (void)handleDebugStateChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshHeader];
        [self.tableView reloadData];
    });
}

- (void)handleSymbolsReady:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)handleRecordUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        AccessRecord *record = notification.object;
        if (![record isKindOfClass:[AccessRecord class]]) {
            return;
        }
        NSInteger row = [self.viewModel indexOfRecord:record];
        if (row == NSNotFound) {
            return;
        }
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        AccessCell *cell = (AccessCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        if ([cell isKindOfClass:[AccessCell class]]) {
            [cell updateLiveValuesWithRecord:record];
        }
    });
}

#pragma mark - Add flow

- (void)accessHeaderDidTapAdd:(AccessHeaderView *)header {
    [self addTapped];
}

- (void)accessHeaderDidTapMore:(AccessHeaderView *)header {
    [self moreTapped];
}

- (void)addTapped {
    if (self.viewModel.watchpointCount >= self.viewModel.slotLimit) {
        [self showAlert:@"硬件槽已满"
                message:@"最多 4 个访问点。请先删除一个，或把相邻字段合并到同一个 8 字节窗口。"];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"添加访问点"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"输入地址"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf afterSheetDismissal:^{
            [weakSelf promptForAddress];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从记录页选择"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[FloatingWindow sharedInstance] showRecord];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.headerView;
        sheet.popoverPresentationController.sourceRect = self.headerView.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptForAddress {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入地址"
                                                                   message:@"十六进制，例如 0x103A2B4C0"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"0x103A2B4C0";
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.font = [AppTheme monospaceFont:13];
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"下一步"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *text = alert.textFields.firstObject.text;
        uint64_t address = [strongSelf parseAddressText:text];
        if (address == 0) {
            [strongSelf showAlert:@"地址无效" message:@"请输入十六进制地址，例如 0x103A2B4C0"];
            return;
        }
        [strongSelf afterSheetDismissal:^{
            [strongSelf promptForType:address];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (uint64_t)parseAddressText:(NSString *)text {
    NSString *value = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"]) {
        value = [value substringFromIndex:2];
    }
    if (value.length == 0) {
        return 0;
    }

    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned long long address = 0;
    if (![scanner scanHexLongLong:&address] || !scanner.isAtEnd) {
        return 0;
    }
    return (uint64_t)address;
}

- (void)promptForType:(uint64_t)address {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"监视类型"
                                                                   message:@"访问 = 只读（load）；写入 = 只写（store）"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"写入"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf addWatchpoint:address type:SSBreakpointTypeWrite];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"访问"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf addWatchpoint:address type:SSBreakpointTypeRead];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.headerView;
        sheet.popoverPresentationController.sourceRect = self.headerView.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addWatchpoint:(uint64_t)address type:(SSBreakpointType)type {
    NSError *error = nil;
    if (![self.viewModel addWatchpoint:address type:type error:&error]) {
        NSString *message = error.localizedDescription;
        [self afterSheetDismissal:^{
            [self showAlert:@"添加失败" message:message];
        }];
        return;
    }
    [self refreshHeader];
}

#pragma mark - More / clear / close

- (void)moreTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"更多"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *debugTitle = self.viewModel.isDebugging ? @"停止调试" : @"启动调试";
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:debugTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf toggleDebugging];
    }]];

    if (self.viewModel.watchpointCount > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"清除全部"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [weakSelf afterSheetDismissal:^{
                [weakSelf confirmClearAll];
            }];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"关闭窗口"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[FloatingWindow sharedInstance] hide];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.headerView;
        sheet.popoverPresentationController.sourceRect = self.headerView.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toggleDebugging {
    if (self.viewModel.isDebugging) {
        [self.viewModel stopDebugging];
    } else {
        [self.viewModel startDebugging];
        if (!self.viewModel.isDebugging) {
            [self afterSheetDismissal:^{
                [self showAlert:@"启动失败" message:@"调试器未能启动，访问点不会生效。"];
            }];
        }
    }
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)bannerTapped {
    [self.viewModel startDebugging];
    [self refreshHeader];
    [self.tableView reloadData];

    if (!self.viewModel.isDebugging) {
        [self showAlert:@"启动失败" message:@"调试器未能启动，访问点不会生效。"];
    }
}

- (void)confirmClearAll {
    NSUInteger count = self.viewModel.watchpointCount;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"清除全部访问点？"
                                            message:[NSString stringWithFormat:
                                                     @"%lu 个访问点及其命中历史都会被清除。",
                                                     (unsigned long)count]
                                     preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清除"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [weakSelf.viewModel removeAllWatchpoints];
        [weakSelf refreshHeader];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.viewModel.watchpointCount;
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

    AccessHit *latestHit = nil;
    for (AccessHit *hit in record.history) {
        if (!latestHit || [hit.timestamp compare:latestHit.timestamp] == NSOrderedDescending) {
            latestHit = hit;
        }
    }

    if (!latestHit) {
        [self showAlert:@"尚未触发" message:@"访问点已生效，等游戏读写这个地址后再点。"];
        return;
    }

    AccessHitInspectorViewController *inspector =
        [[AccessHitInspectorViewController alloc] initWithRecord:record hit:latestHit];
    inspector.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:inspector animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.viewModel removeWatchpointAtIndex:indexPath.row];
    }
}

#pragma mark - Long press menu

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }

    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) {
        return;
    }

    AccessRecord *record = [self.viewModel recordAtIndex:indexPath.row];
    if (!record) {
        return;
    }

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"0x%llX", record.address]
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"触发历史"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        AccessDetailsViewController *detail = [[AccessDetailsViewController alloc] init];
        detail.record = record;
        detail.modalPresentationStyle = UIModalPresentationPageSheet;
        [strongSelf afterSheetDismissal:^{
            [strongSelf presentViewController:detail animated:YES completion:nil];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制地址"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"0x%llX", record.address];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看内存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf showMemoryForRecord:record assembly:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看反汇编"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf showMemoryForRecord:record assembly:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"重命名"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf afterSheetDismissal:^{
            [weakSelf renameRecord:record];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"清零命中"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf.viewModel resetHitCountForAddress:record.address];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [weakSelf afterSheetDismissal:^{
            [weakSelf confirmDeleteRecord:record];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showMemoryForRecord:(AccessRecord *)record assembly:(BOOL)assembly {
    FloatingWindow *floating = [FloatingWindow sharedInstance];
    MemoryPages *memory = floating.memoryViewController;
    [floating showMemory];
    [memory loadViewIfNeeded];
    if (assembly) {
        [memory selectDataType:4];
    }
    [memory jumpToAddress:record.address];
}

- (void)renameRecord:(AccessRecord *)record {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"重命名访问点"
                                            message:@"留空则恢复显示符号"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = record.label;
        textField.placeholder = @"例如：玩家血量";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *text = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        record.label = text.length > 0 ? text : nil;

        NSInteger row = [strongSelf.viewModel indexOfRecord:record];
        if (row != NSNotFound) {
            [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                                        withRowAnimation:UITableViewRowAnimationNone];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteRecord:(AccessRecord *)record {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"删除访问点？"
                                            message:[NSString stringWithFormat:@"0x%llX 及其命中历史会被清除。",
                                                     record.address]
                                     preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSInteger row = [strongSelf.viewModel indexOfRecord:record];
        if (row != NSNotFound) {
            [strongSelf.viewModel removeWatchpointAtIndex:(NSUInteger)row];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AccessCellDelegate

- (void)accessCellDidChangeEnabled:(BOOL)enabled forAddress:(uint64_t)address {
    NSError *error = nil;
    if (![self.viewModel setEnabled:enabled forAddress:address error:&error]) {
        [self showAlert:@"操作失败" message:error.localizedDescription];
        [self.tableView reloadData];
    }
    [self refreshHeader];
}

- (void)accessCellDidTapTypeForAddress:(uint64_t)address {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"监视类型"
                                                                   message:@"访问 = 只读（load）；写入 = 只写（store）"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"写入"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf changeType:SSBreakpointTypeWrite forAddress:address];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"访问"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf changeType:SSBreakpointTypeRead forAddress:address];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)changeType:(SSBreakpointType)type forAddress:(uint64_t)address {
    NSError *error = nil;
    if (![self.viewModel setType:type forAddress:address error:&error]) {
        NSString *message = error.localizedDescription;
        [self afterSheetDismissal:^{
            [self showAlert:@"切换类型失败" message:message];
        }];
    }
    [self.tableView reloadData];
    [self refreshHeader];
}

#pragma mark - Helpers

- (void)afterSheetDismissal:(dispatch_block_t)block {
    if (!block) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
