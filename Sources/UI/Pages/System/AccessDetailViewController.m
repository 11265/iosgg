#import "UI/Pages/System/AccessDetailViewController.h"
#import "UI/Pages/System/AccessRegisterViewController.h"
#import "Services/LogService.h"
#import "UI/Components/ThemeConfig.h"
#import "UI/Pages/Memory/MemoryPage.h"
#import "UI/Components/FloatingWindow.h"

@interface AccessDetailsViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;

@end

@implementation AccessDetailsViewController

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
        [topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
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
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleRecordUpdate:) 
                                                 name:kAccessRecordDidUpdateNotification 
                                               object:nil];
}

- (void)handleRecordUpdate:(NSNotification *)note {
    AccessRecord *updatedRecord = note.object;
    if (updatedRecord == self.record) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }
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
        typeStr = @"Write";
        typeColor = [AppTheme writeTypeColor];
    } else if (hit.type == SSBreakpointTypeRead) {
        typeStr = @"Read";
        typeColor = [AppTheme readTypeColor];
    } else if (hit.type == SSBreakpointTypeReadWrite) {
        typeStr = @"R/W";
        typeColor = [UIColor colorWithRed:0.8f green:0.6f blue:1.0f alpha:1.0f];
    } else {
        typeStr = @"Exec";
        typeColor = [AppTheme textColor];
    }
    
    cell.textLabel.text = [NSString stringWithFormat:@"PC: %@  |  %@", [self formatHex:hit.instructionAddr], typeStr];
    cell.textLabel.textColor = typeColor;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timeStr = [formatter stringFromDate:hit.timestamp];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Val: %@  |  Count: %ld  |  %@", [self formatHex:hit.value], (long)hit.hitCount, timeStr];
    
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
    
    AccessRegisterViewController *vc = [[AccessRegisterViewController alloc] init];
    vc.registers = hit.registers;
    vc.callStack = hit.callStack;
    vc.instructionAddr = hit.instructionAddr;
    vc.memoryAddress = hit.memoryAddress;
    
    [LoggingService log:@"[访问详情] 准备显示 AccessRegisterViewController"];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timeStr = [formatter stringFromDate:hit.timestamp];
    
    NSString *typeStr;
    if (hit.type == SSBreakpointTypeWrite) {
        typeStr = @"Write";
    } else if (hit.type == SSBreakpointTypeRead) {
        typeStr = @"Read";
    } else if (hit.type == SSBreakpointTypeReadWrite) {
        typeStr = @"R/W";
    } else {
        typeStr = @"Exec";
    }
    
    vc.accessInfo = [NSString stringWithFormat:@"Address: %@\nValue:   %@\nPC:      %@\nType:    %@\nTime:    %@",
                     [self formatHex:self.record.address],
                     [self formatHex:hit.value],
                     [self formatHex:hit.instructionAddr],
                     typeStr,
                     timeStr];
                     
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:vc animated:YES completion:nil];
}

@end
