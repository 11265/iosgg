#import "UI/Pages/Debugger/Access/AccessDetailViewController.h"
#import "UI/Pages/Debugger/AccessHitInspectorViewController.h"
#import "Services/LogService.h"
#import "UI/Components/ThemeConfig.h"
#import "UI/Pages/Memory/MemoryPage.h"
#import "UI/Components/FloatingWindow.h"
#import "Services/SSSymbolicator.h"

@interface AccessDetailsViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@property (nonatomic, assign) BOOL reloadScheduled;

@end

@implementation AccessDetailsViewController

- (NSDateFormatter *)timeFormatter {
    if (!_timeFormatter) {
        _timeFormatter = [[NSDateFormatter alloc] init];
        [_timeFormatter setDateFormat:@"HH:mm:ss"];
    }
    return _timeFormatter;
}

- (NSString *)formatHex:(uint64_t)value {
    if (value == 0) return @"0x0";
    NSString *fullHex = [NSString stringWithFormat:@"%llx", value];
    NSString *trimmed = [fullHex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0"]];
    if (trimmed.length == 0) return @"0x0";
    return [NSString stringWithFormat:@"0x%@", trimmed];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [AppTheme backgroundColor];
    
    UIView *topBar = [[UIView alloc] init];
    topBar.backgroundColor = [AppTheme titleBackgroundColor];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:topBar];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Trigger History";
    titleLabel.textColor = [AppTheme textColor];
    titleLabel.font = [AppTheme boldFont:17];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:titleLabel];
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [closeButton setTitleColor:[AppTheme textHighlightColor] forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:closeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:50],
        
        [closeButton.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [closeButton.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-15],
        
        [titleLabel.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [titleLabel.centerXAnchor constraintEqualToAnchor:topBar.centerXAnchor]
    ]];
    
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [AppTheme borderColor];
    [self.view addSubview:self.tableView];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleRecordUpdate:) 
                                                 name:kAccessRecordDidUpdateNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSymbolsReady:)
                                                 name:SSSymbolicatorObjCMethodsDidBecomeReadyNotification
                                               object:nil];
}

- (void)handleRecordUpdate:(NSNotification *)note {
    AccessRecord *updatedRecord = note.object;
    if (updatedRecord != self.record) {
        return;
    }
    // 高频命中时每来一条就 reload 会把主线程刷爆：0.25s 合并一次
    if (self.reloadScheduled) {
        return;
    }
    self.reloadScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.reloadScheduled = NO;
        [strongSelf.tableView reloadData];
    });
}

- (void)handleSymbolsReady:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.record.history.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"HitCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [AppTheme textColor];
        cell.textLabel.font = [AppTheme monospaceBoldFont:14];
        cell.detailTextLabel.textColor = [AppTheme textDisabledColor];
        cell.detailTextLabel.font = [AppTheme monospaceFont:12];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    
    AccessHit *hit = self.record.history[indexPath.row];
    
    NSString *typeStr;
    UIColor *typeColor;
    if (hit.type == SSBreakpointTypeWrite) {
        typeStr = @"写入";
        typeColor = [AppTheme writeTypeColor];
    } else {
        typeStr = @"访问";
        typeColor = [UIColor colorWithRed:0.8f green:0.6f blue:1.0f alpha:1.0f];
    }
    
    SSSymbol *symbol = [[SSSymbolicator shared] symbolForAddress:hit.instructionAddr];
    NSString *symbolText = symbol.shortText;
    if (symbolText.length == 0) {
        symbolText = [self formatHex:hit.instructionAddr];
    }
    cell.textLabel.text = [NSString stringWithFormat:@"%@  |  %@", symbolText, typeStr];
    cell.textLabel.textColor = typeColor;
    
    NSString *timeStr = [self.timeFormatter stringFromDate:hit.timestamp];
    NSString *moduleText = symbol.moduleText ?: @"";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · Val %@ | Count %ld | %@",
                                 moduleText,
                                 [self formatHex:hit.value],
                                 (long)hit.hitCount,
                                 timeStr];
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    [LoggingService log:@"[访问详情] 点击行: %ld", (long)indexPath.row];
    
    AccessHit *hit = self.record.history[indexPath.row];
    
    [LoggingService log:@"[访问详情] hit.instructionAddr: 0x%llX", hit.instructionAddr];
    [LoggingService log:@"[访问详情] hit.registers: %lu 项", (unsigned long)hit.registers.count];
    [LoggingService log:@"[访问详情] hit.callStack: %lu 项", (unsigned long)hit.callStack.count];
    
    AccessHitInspectorViewController *vc =
        [[AccessHitInspectorViewController alloc] initWithRecord:self.record hit:hit];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:vc animated:YES completion:nil];
}

@end
