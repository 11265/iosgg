#import "UI/Pages/Debugger/AccessHitInspectorViewController.h"

#import <mach/mach.h>
#import <mach/vm_region.h>
#import <unistd.h>
#import <stdlib.h>

#import "Modules/ProcessInfo/ProcessMemory.h"
#import "Models/AccessRecord.h"
#import "Modules/Debugger/SSDebugger.h"
#import "Modules/MemoryAnalysis/ARM64Assembler.h"
#import "Modules/MemoryAnalysis/SSInstructionExplainer.h"
#import "Services/LogService.h"
#import "Services/SSSymbol.h"
#import "Services/SSSymbolicator.h"
#import "UI/Components/SSDisassemblyCell.h"
#import "UI/Components/ThemeConfig.h"

static const NSInteger kDisassemblyBefore = 32;
static const NSInteger kDisassemblyAfter = 32;
static const NSInteger kFullSymbolFrameLimit = 12;
static const NSInteger kMemoryRowCount = 16;
static const NSInteger kMemoryBytesPerRow = 8;

typedef NS_ENUM(NSInteger, SSHInspectorMode) {
    SSHInspectorModeOverview = 0,
    SSHInspectorModeDisassembly,
    SSHInspectorModeCallStack,
    SSHInspectorModeRegisters,
    SSHInspectorModeMemory
};

static NSArray<NSString *> *SSRegisterNames(void) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[@"x0", @"x1", @"x2", @"x3", @"x4", @"x5", @"x6", @"x7",
                  @"x8", @"x9", @"x10", @"x11", @"x12", @"x13", @"x14", @"x15",
                  @"x16", @"x17", @"x18", @"x19", @"x20", @"x21", @"x22", @"x23",
                  @"x24", @"x25", @"x26", @"x27", @"x28", @"fp", @"lr", @"sp", @"pc", @"cpsr"];
    });
    return names;
}

@interface AccessHitInspectorViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) AccessRecord *record;
@property (nonatomic, strong) AccessHit *hit;

@property (nonatomic, assign) SSHInspectorMode mode;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@property (nonatomic, assign) BOOL reloadScheduled;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UIView *summaryView;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *symbolLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *explanationLabel;

@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, strong) NSMutableArray<NSNumber *> *codeHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *dataHistory;

@property (nonatomic, strong) NSMutableArray<SSDisassemblyLine *> *disassemblyLines;
@property (nonatomic, assign) uint64_t builtCodeAddress;

@property (nonatomic, strong) NSArray<NSDictionary *> *memoryRows;
@property (nonatomic, assign) uint64_t builtDataAddress;

@property (nonatomic, strong) NSArray<NSDictionary *> *overviewRows;
@property (nonatomic, strong) NSArray<NSDictionary *> *registerRows;
@property (nonatomic, strong) NSArray<NSDictionary *> *frameRows;

@end

@implementation AccessHitInspectorViewController

- (instancetype)initWithRecord:(AccessRecord *)record hit:(AccessHit *)hit {
    if (self = [super init]) {
        _record = record;
        _hit = hit;
        _codeHistory = [NSMutableArray arrayWithObject:@(hit.instructionAddr)];
        uint64_t dataAddress = hit.memoryAddress != 0 ? hit.memoryAddress : record.address;
        _dataHistory = [NSMutableArray arrayWithObject:@(dataAddress)];
        _mode = SSHInspectorModeDisassembly;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [AppTheme backgroundColor];

    [self setupTopBar];
    [self setupSummary];
    [self setupSegmentedControl];
    [self setupActionBar];
    [self setupTableView];

    [self buildStaticData];
    [self refreshSummary];
    [self updateTitle];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSymbolsReady:)
                                                 name:SSSymbolicatorObjCMethodsDidBecomeReadyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRecordUpdate:)
                                                 name:kAccessRecordDidUpdateNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI

- (void)setupTopBar {
    self.topBar = [[UIView alloc] init];
    self.topBar.backgroundColor = [AppTheme titleBackgroundColor];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topBar];

    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setTitle:@"‹ 返回" forState:UIControlStateNormal];
    [self.backButton setTitleColor:[AppTheme textHighlightColor] forState:UIControlStateNormal];
    self.backButton.titleLabel.font = [AppTheme regularFont:14];
    self.backButton.hidden = YES;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backButton];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[AppTheme textHighlightColor] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [AppTheme regularFont:14];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.closeButton];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [AppTheme monospaceFont:12];
    self.titleLabel.textColor = [AppTheme textColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBar addSubview:self.titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topBar.heightAnchor constraintEqualToConstant:44],

        [self.backButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:8],
        [self.backButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.backButton.widthAnchor constraintEqualToConstant:64],

        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-8],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:48],

        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.topBar.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.topBar.leadingAnchor constant:78],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.topBar.trailingAnchor constant:-60]
    ]];
}

- (void)setupSummary {
    self.summaryView = [[UIView alloc] init];
    self.summaryView.backgroundColor = [UIColor colorWithWhite:0.10f alpha:1.0f];
    self.summaryView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.summaryView];

    self.addressLabel = [[UILabel alloc] init];
    self.addressLabel.font = [AppTheme monospaceBoldFont:13];
    self.addressLabel.textColor = [AppTheme textColor];
    self.addressLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.summaryView addSubview:self.addressLabel];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [AppTheme monospaceBoldFont:13];
    self.valueLabel.textColor = [AppTheme valueColor];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                     forAxis:UILayoutConstraintAxisHorizontal];
    [self.summaryView addSubview:self.valueLabel];

    self.symbolLabel = [[UILabel alloc] init];
    self.symbolLabel.font = [AppTheme monospaceFont:11];
    self.symbolLabel.textColor = [AppTheme textHighlightColor];
    self.symbolLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.symbolLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.summaryView addSubview:self.symbolLabel];

    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.font = [AppTheme regularFont:10];
    self.metaLabel.textColor = [AppTheme textDisabledColor];
    self.metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.summaryView addSubview:self.metaLabel];

    self.explanationLabel = [[UILabel alloc] init];
    self.explanationLabel.font = [AppTheme monospaceFont:10];
    self.explanationLabel.textColor = [AppTheme textHighlightColor];
    self.explanationLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.explanationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.summaryView addSubview:self.explanationLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.summaryView.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.summaryView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.summaryView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.summaryView.heightAnchor constraintEqualToConstant:98],

        [self.addressLabel.topAnchor constraintEqualToAnchor:self.summaryView.topAnchor constant:7],
        [self.addressLabel.leadingAnchor constraintEqualToAnchor:self.summaryView.leadingAnchor constant:10],
        [self.addressLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.valueLabel.leadingAnchor constant:-8],

        [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.addressLabel.centerYAnchor],
        [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.summaryView.trailingAnchor constant:-10],
        [self.valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:60],

        [self.symbolLabel.topAnchor constraintEqualToAnchor:self.addressLabel.bottomAnchor constant:2],
        [self.symbolLabel.leadingAnchor constraintEqualToAnchor:self.summaryView.leadingAnchor constant:10],
        [self.symbolLabel.trailingAnchor constraintEqualToAnchor:self.summaryView.trailingAnchor constant:-10],

        [self.metaLabel.topAnchor constraintEqualToAnchor:self.symbolLabel.bottomAnchor constant:1],
        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.summaryView.leadingAnchor constant:10],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:self.summaryView.trailingAnchor constant:-10],

        [self.explanationLabel.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:2],
        [self.explanationLabel.leadingAnchor constraintEqualToAnchor:self.summaryView.leadingAnchor constant:10],
        [self.explanationLabel.trailingAnchor constraintEqualToAnchor:self.summaryView.trailingAnchor constant:-10]
    ]];
}

- (void)setupSegmentedControl {
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:
        @[@"概览", @"反汇编", @"调用栈", @"寄存器", @"内存"]];
    self.segmentedControl.selectedSegmentIndex = self.mode;
    self.segmentedControl.selectedSegmentTintColor = [AppTheme titleBackgroundActiveColor];
    [self.segmentedControl setTitleTextAttributes:@{
        NSFontAttributeName: [AppTheme regularFont:11],
        NSForegroundColorAttributeName: [AppTheme textColor]
    } forState:UIControlStateNormal];
    [self.segmentedControl setTitleTextAttributes:@{
        NSFontAttributeName: [AppTheme boldFont:11],
        NSForegroundColorAttributeName: [AppTheme textColor]
    } forState:UIControlStateSelected];
    [self.segmentedControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.segmentedControl];

    [NSLayoutConstraint activateConstraints:@[
        [self.segmentedControl.topAnchor constraintEqualToAnchor:self.summaryView.bottomAnchor constant:6],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.segmentedControl.heightAnchor constraintEqualToConstant:26]
    ]];
}

- (void)setupActionBar {
    self.actionBar = [[UIView alloc] init];
    self.actionBar.backgroundColor = [AppTheme titleBackgroundColor];
    self.actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.actionBar];

    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = [AppTheme borderColor];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionBar addSubview:separator];

    UIButton *breakpointButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [breakpointButton setTitle:@"设执行断点" forState:UIControlStateNormal];
    [breakpointButton setTitleColor:[AppTheme textHighlightColor] forState:UIControlStateNormal];
    breakpointButton.titleLabel.font = [AppTheme regularFont:12];
    [breakpointButton addTarget:self action:@selector(breakpointTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyButton setTitle:@"复制" forState:UIControlStateNormal];
    [copyButton setTitleColor:[AppTheme textColor] forState:UIControlStateNormal];
    copyButton.titleLabel.font = [AppTheme regularFont:12];
    [copyButton addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [exportButton setTitle:@"导出" forState:UIControlStateNormal];
    [exportButton setTitleColor:[AppTheme textColor] forState:UIControlStateNormal];
    exportButton.titleLabel.font = [AppTheme regularFont:12];
    [exportButton addTarget:self action:@selector(exportTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[breakpointButton, copyButton, exportButton]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionBar addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.actionBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.actionBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.actionBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.actionBar.heightAnchor constraintEqualToConstant:44],

        [separator.topAnchor constraintEqualToAnchor:self.actionBar.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:self.actionBar.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.actionBar.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],

        [stack.topAnchor constraintEqualToAnchor:self.actionBar.topAnchor constant:4],
        [stack.leadingAnchor constraintEqualToAnchor:self.actionBar.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:self.actionBar.trailingAnchor constant:-8],
        [stack.bottomAnchor constraintEqualToAnchor:self.actionBar.bottomAnchor constant:-4]
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [AppTheme borderColor];
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.tableView.rowHeight = 44;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:[SSDisassemblyCell class]
           forCellReuseIdentifier:[SSDisassemblyCell reuseIdentifier]];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:6],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.actionBar.topAnchor]
    ]];
}

- (NSDateFormatter *)timeFormatter {
    if (!_timeFormatter) {
        _timeFormatter = [[NSDateFormatter alloc] init];
        [_timeFormatter setDateFormat:@"HH:mm:ss"];
    }
    return _timeFormatter;
}

#pragma mark - Address state

- (uint64_t)currentCodeAddress {
    return self.codeHistory.lastObject.unsignedLongLongValue;
}

- (uint64_t)currentDataAddress {
    return self.dataHistory.lastObject.unsignedLongLongValue;
}

- (void)pushCodeAddress:(uint64_t)address {
    if (address == 0) {
        return;
    }
    if (address != [self currentCodeAddress]) {
        [self.codeHistory addObject:@(address)];
    }
    [self switchToMode:SSHInspectorModeDisassembly];
}

- (void)pushDataAddress:(uint64_t)address {
    if (address == 0) {
        return;
    }
    if (address != [self currentDataAddress]) {
        [self.dataHistory addObject:@(address)];
    }
    [self switchToMode:SSHInspectorModeMemory];
}

- (void)switchToMode:(SSHInspectorMode)mode {
    self.mode = mode;
    self.segmentedControl.selectedSegmentIndex = mode;
    self.builtCodeAddress = 0;
    self.builtDataAddress = 0;
    [self updateTitle];
    [self.tableView reloadData];
}

#pragma mark - Data

- (NSString *)typeText {
    return self.hit.type == SSBreakpointTypeWrite ? @"写入" : @"访问";
}

- (NSString *)hexValue:(uint64_t)value width:(uint8_t)size {
    switch (size) {
        case 1: return [NSString stringWithFormat:@"0x%02llX", (unsigned long long)(value & 0xFF)];
        case 2: return [NSString stringWithFormat:@"0x%04llX", (unsigned long long)(value & 0xFFFF)];
        case 4: return [NSString stringWithFormat:@"0x%08llX", (unsigned long long)(value & 0xFFFFFFFF)];
        default: return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
    }
}

- (DisassembledInstruction *)instructionAtAddress:(uint64_t)address {
    if (address == 0) {
        return nil;
    }
    uint32_t instruction = 0;
    mach_vm_size_t outsize = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                              (mach_vm_address_t)address,
                                              sizeof(instruction),
                                              (mach_vm_address_t)&instruction,
                                              &outsize);
    if (kr != KERN_SUCCESS || outsize != sizeof(instruction)) {
        return nil;
    }
    return [ARM64Assembler disassemble:instruction atAddress:address];
}

- (NSString *)instructionTextAt:(uint64_t)address {
    DisassembledInstruction *instruction = [self instructionAtAddress:address];
    if (!instruction) {
        return @"-";
    }
    NSString *mnemonic = instruction.mnemonic.length > 0 ? instruction.mnemonic : @".word";
    return instruction.opStr.length > 0
        ? [NSString stringWithFormat:@"%@ %@", mnemonic, instruction.opStr]
        : mnemonic;
}

- (void)refreshSummary {
    uint8_t size = self.hit.accessSize ?: 8;

    self.addressLabel.text = [NSString stringWithFormat:@"0x%llX  %@  %uB",
                              (unsigned long long)self.record.address,
                              [self typeText],
                              (unsigned)size];
    self.valueLabel.text = [self hexValue:self.hit.value width:size];

    SSSymbol *pcSymbol = [[SSSymbolicator shared] symbolForAddress:self.hit.instructionAddr];
    NSString *pcText = pcSymbol.shortText;
    if (pcText.length == 0) {
        pcText = [NSString stringWithFormat:@"0x%llX", (unsigned long long)self.hit.instructionAddr];
    }
    self.symbolLabel.text = [NSString stringWithFormat:@"触发: %@", pcText];

    NSMutableString *meta = [NSMutableString string];
    if (self.hit.memoryAddress != 0 && self.hit.memoryAddress != self.record.address) {
        [meta appendFormat:@"实际 0x%llX · ", (unsigned long long)self.hit.memoryAddress];
    }
    if (self.hit.threadId != 0) {
        [meta appendFormat:@"线程 0x%X · ", self.hit.threadId];
    }
    [meta appendFormat:@"命中 %ld 次 · %@",
     (long)self.hit.hitCount,
     [self.timeFormatter stringFromDate:self.hit.timestamp]];
    self.metaLabel.text = meta;

    DisassembledInstruction *instruction = [self instructionAtAddress:self.hit.instructionAddr];
    SSInstructionExplanation *explanation =
        [SSInstructionExplainer explainInstruction:instruction
                                               far:self.hit.memoryAddress
                                         registers:self.hit.registers
                                             width:size];
    if (explanation.summary.length > 0) {
        self.explanationLabel.text = explanation.summary;
        self.explanationLabel.textColor = explanation.isWrite ? [AppTheme valueColor]
                                                              : [AppTheme textHighlightColor];
    } else if (instruction) {
        self.explanationLabel.text = [NSString stringWithFormat:@"%@ %@",
                                      instruction.mnemonic, instruction.opStr];
        self.explanationLabel.textColor = [AppTheme textDisabledColor];
    } else {
        self.explanationLabel.text = @"";
    }
}

- (void)buildStaticData {
    [self buildOverviewRows];
    [self buildRegisterRows];
    [self buildFrameRows];
}

- (void)buildOverviewRows {
    uint8_t size = self.hit.accessSize ?: 8;
    SSSymbol *pcSymbol = [[SSSymbolicator shared] symbolForAddress:self.hit.instructionAddr];
    uint64_t dataAddress = self.hit.memoryAddress != 0 ? self.hit.memoryAddress : self.record.address;

    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    [self addOverviewRow:rows title:@"访问点"
                   value:[NSString stringWithFormat:@"0x%llX", (unsigned long long)self.record.address]
                  action:@"data"
                 address:self.record.address];
    [self addOverviewRow:rows title:@"实际访问"
                   value:(self.hit.memoryAddress != 0
                          ? [NSString stringWithFormat:@"0x%llX", (unsigned long long)self.hit.memoryAddress]
                          : @"-")
                  action:@"data"
                 address:dataAddress];
    [self addOverviewRow:rows title:@"当前值"
                   value:[self hexValue:self.hit.value width:size]
                  action:@"data"
                 address:dataAddress];
    [self addOverviewRow:rows title:@"类型 / 宽度"
                   value:[NSString stringWithFormat:@"%@ · %uB", [self typeText], (unsigned)size]
                  action:nil
                 address:0];
    [self addOverviewRow:rows title:@"线程"
                   value:(self.hit.threadId != 0
                          ? [NSString stringWithFormat:@"0x%X", self.hit.threadId]
                          : @"-")
                  action:nil
                 address:0];
    [self addOverviewRow:rows title:@"时间"
                   value:[self.timeFormatter stringFromDate:self.hit.timestamp]
                  action:nil
                 address:0];
    [self addOverviewRow:rows title:@"本次命中"
                   value:[NSString stringWithFormat:@"%ld", (long)self.hit.hitCount]
                  action:nil
                 address:0];
    [self addOverviewRow:rows title:@"记录总命中"
                   value:[NSString stringWithFormat:@"%ld", (long)self.record.hitCount]
                  action:nil
                 address:0];
    [self addOverviewRow:rows title:@"触发指令"
                   value:[self instructionTextAt:self.hit.instructionAddr]
                  action:@"code"
                 address:self.hit.instructionAddr];

    DisassembledInstruction *instruction = [self instructionAtAddress:self.hit.instructionAddr];
    SSInstructionExplanation *explanation =
        [SSInstructionExplainer explainInstruction:instruction
                                               far:self.hit.memoryAddress
                                         registers:self.hit.registers
                                             width:size];
    [self addOverviewRow:rows title:@"指令解释"
                   value:(explanation.summary.length > 0 ? explanation.summary : @"-")
                  action:nil
                 address:0];

    [self addOverviewRow:rows title:@"触发函数"
                   value:(pcSymbol.shortText.length > 0 ? pcSymbol.shortText : @"-")
                  action:@"code"
                 address:self.hit.instructionAddr];
    [self addOverviewRow:rows title:@"模块偏移"
                   value:(pcSymbol.moduleText.length > 0 ? pcSymbol.moduleText : @"-")
                  action:@"code"
                 address:self.hit.instructionAddr];
    [self addOverviewRow:rows title:@"调用栈"
                   value:[NSString stringWithFormat:@"%lu 帧", (unsigned long)self.hit.callStack.count]
                  action:@"callstack"
                 address:0];

    self.overviewRows = rows;
}

- (void)addOverviewRow:(NSMutableArray<NSDictionary *> *)rows
                 title:(NSString *)title
                 value:(NSString *)value {
    [self addOverviewRow:rows title:title value:value action:nil address:0];
}

- (void)addOverviewRow:(NSMutableArray<NSDictionary *> *)rows
                 title:(NSString *)title
                 value:(NSString *)value
                action:(NSString *)action
               address:(uint64_t)address {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    row[@"title"] = title;
    row[@"value"] = value.length > 0 ? value : @"-";
    row[@"addressValue"] = @(address);
    if (action.length > 0) {
        row[@"action"] = action;
    }
    [rows addObject:row];
}

- (void)buildRegisterRows {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSString *name in SSRegisterNames()) {
        NSNumber *number = self.hit.registers[name];
        uint64_t value = number.unsignedLongLongValue;
        [rows addObject:@{
            @"name": name,
            @"value": number ? [NSString stringWithFormat:@"0x%llX", value] : @"--",
            @"addressValue": @(value),
            @"hasValue": @(number != nil)
        }];
    }
    self.registerRows = rows;
}

- (void)buildFrameRows {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    NSArray *callStack = self.hit.callStack ?: @[];

    for (NSUInteger i = 0; i < callStack.count; i++) {
        NSString *addressText = callStack[i];
        uint64_t address = strtoull([addressText UTF8String], NULL, 16);

        NSString *symbolText = @"";
        NSString *moduleText = @"";
        if (i < (NSUInteger)kFullSymbolFrameLimit) {
            SSSymbol *symbol = (i == 0)
                ? [[SSSymbolicator shared] symbolForAddress:address]
                : [[SSSymbolicator shared] symbolForReturnAddress:address];
            symbolText = symbol.shortText ?: @"";
            moduleText = symbol.moduleText ?: @"";
        }

        [rows addObject:@{
            @"index": @(i),
            @"address": addressText,
            @"addressValue": @(address),
            @"symbol": symbolText,
            @"module": moduleText
        }];
    }
    self.frameRows = rows;
}

#pragma mark - Disassembly

- (void)ensureDisassembly {
    if (self.mode != SSHInspectorModeDisassembly) {
        return;
    }
    uint64_t address = [self currentCodeAddress];
    if (self.disassemblyLines != nil && self.builtCodeAddress == address) {
        return;
    }
    self.builtCodeAddress = address;
    self.disassemblyLines = [[self buildDisassemblyAt:address] mutableCopy];
}

- (NSArray<SSDisassemblyLine *> *)buildDisassemblyAt:(uint64_t)center {
    NSInteger count = kDisassemblyBefore + kDisassemblyAfter + 1;
    uint64_t start = center;
    if (start > (uint64_t)kDisassemblyBefore * 4) {
        start -= (uint64_t)kDisassemblyBefore * 4;
    } else {
        start = 0;
    }
    start &= ~3ULL;

    NSMutableArray<SSDisassemblyLine *> *lines = [NSMutableArray arrayWithCapacity:(NSUInteger)count];

    uint8_t *buffer = (uint8_t *)malloc((size_t)count * 4);
    BOOL bulkRead = NO;
    if (buffer) {
        mach_vm_size_t outsize = 0;
        kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                                  (mach_vm_address_t)start,
                                                  (mach_vm_size_t)count * 4,
                                                  (mach_vm_address_t)buffer,
                                                  &outsize);
        if (kr == KERN_SUCCESS && outsize >= 4) {
            bulkRead = YES;
            NSInteger available = (NSInteger)(outsize / 4);
            for (NSInteger i = 0; i < available; i++) {
                uint32_t instruction = 0;
                memcpy(&instruction, buffer + i * 4, sizeof(instruction));
                [lines addObject:[self lineForInstruction:instruction
                                                       at:start + (uint64_t)i * 4
                                                   center:center]];
            }
        }
        free(buffer);
    }

    if (!bulkRead) {
        for (NSInteger i = 0; i < count; i++) {
            uint64_t address = start + (uint64_t)i * 4;
            uint32_t instruction = 0;
            mach_vm_size_t outsize = 0;
            kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                                      (mach_vm_address_t)address,
                                                      sizeof(instruction),
                                                      (mach_vm_address_t)&instruction,
                                                      &outsize);
            if (kr == KERN_SUCCESS && outsize == sizeof(instruction)) {
                [lines addObject:[self lineForInstruction:instruction at:address center:center]];
            }
        }
    }

    return lines;
}

- (SSDisassemblyLine *)lineForInstruction:(uint32_t)instruction
                                       at:(uint64_t)address
                                   center:(uint64_t)center {
    DisassembledInstruction *decoded = [ARM64Assembler disassemble:instruction atAddress:address];

    SSDisassemblyLine *line = [[SSDisassemblyLine alloc] init];
    line.address = address;
    line.bytesText = [NSString stringWithFormat:@"%02X %02X %02X %02X",
                      instruction & 0xFF,
                      (instruction >> 8) & 0xFF,
                      (instruction >> 16) & 0xFF,
                      (instruction >> 24) & 0xFF];
    line.mnemonic = decoded.mnemonic.length > 0 ? decoded.mnemonic : @".word";
    line.operands = decoded.opStr ?: @"";
    line.isCurrent = (address == center);

    if (decoded.isBranch && decoded.targetAddress != 0) {
        line.isBranch = YES;
        line.branchTarget = decoded.targetAddress;

        SSSymbol *target = [[SSSymbolicator shared] symbolForAddress:decoded.targetAddress];
        NSString *targetText = target.shortText;
        if (targetText.length == 0) {
            targetText = [NSString stringWithFormat:@"0x%llX", (unsigned long long)decoded.targetAddress];
        }
        line.annotation = [NSString stringWithFormat:@"→ %@", targetText];
    }

    return line;
}

#pragma mark - Memory

- (void)ensureMemory {
    if (self.mode != SSHInspectorModeMemory) {
        return;
    }
    uint64_t center = [self currentDataAddress];
    if (self.memoryRows != nil && self.builtDataAddress == center) {
        return;
    }
    self.builtDataAddress = center;
    self.memoryRows = [self buildMemoryAt:center];
}

- (NSArray<NSDictionary *> *)buildMemoryAt:(uint64_t)center {
    if (center == 0) {
        return @[];
    }

    uint64_t base = center & ~7ULL;
    base = base > 64 ? base - 64 : 0;
    NSInteger total = kMemoryRowCount * kMemoryBytesPerRow;

    uint8_t *buffer = (uint8_t *)malloc((size_t)total);
    if (!buffer) {
        return @[];
    }
    memset(buffer, 0, (size_t)total);

    mach_vm_size_t outsize = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                              (mach_vm_address_t)base,
                                              (mach_vm_size_t)total,
                                              (mach_vm_address_t)buffer,
                                              &outsize);

    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithCapacity:(NSUInteger)kMemoryRowCount];
    if (kr == KERN_SUCCESS && outsize >= kMemoryBytesPerRow) {
        NSInteger available = (NSInteger)(outsize / kMemoryBytesPerRow);
        for (NSInteger i = 0; i < available; i++) {
            NSData *data = [NSData dataWithBytes:buffer + i * kMemoryBytesPerRow
                                          length:kMemoryBytesPerRow];
            [rows addObject:@{@"address": @(base + (uint64_t)i * kMemoryBytesPerRow), @"data": data}];
        }
    } else {
        for (NSInteger i = 0; i < kMemoryRowCount; i++) {
            uint64_t address = base + (uint64_t)i * kMemoryBytesPerRow;
            uint64_t value = 0;
            mach_vm_size_t rowOutsize = 0;
            kern_return_t rowKr = mach_vm_read_overwrite(mach_task_self(),
                                                         (mach_vm_address_t)address,
                                                         sizeof(value),
                                                         (mach_vm_address_t)&value,
                                                         &rowOutsize);
            if (rowKr == KERN_SUCCESS && rowOutsize == sizeof(value)) {
                NSData *data = [NSData dataWithBytes:&value length:sizeof(value)];
                [rows addObject:@{@"address": @(address), @"data": data}];
            } else {
                [rows addObject:@{@"address": @(address), @"data": [NSData data]}];
            }
        }
    }

    free(buffer);
    return rows;
}

- (NSAttributedString *)hexTextForRow:(NSDictionary *)row {
    uint64_t address = [row[@"address"] unsignedLongLongValue];
    NSData *data = row[@"data"];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;

    UIFont *font = [AppTheme monospaceFont:10];
    UIColor *addressColor = [AppTheme textDisabledColor];
    UIColor *normalColor = [AppTheme textColor];
    UIColor *disabledColor = [AppTheme textDisabledColor];
    UIColor *highlightColor = [AppTheme valueColor];
    UIColor *highlightBackground = [UIColor colorWithRed:0.26f green:0.59f blue:0.98f alpha:0.28f];

    uint64_t far = self.hit.memoryAddress;
    uint8_t width = self.hit.accessSize ?: 8;

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];

    NSString *addressText = [NSString stringWithFormat:@"0x%09llX  ", address];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:addressText
                                                                 attributes:@{
                                                                     NSFontAttributeName: font,
                                                                     NSForegroundColorAttributeName: addressColor
                                                                 }]];

    for (NSInteger i = 0; i < kMemoryBytesPerRow; i++) {
        BOOL readable = (NSUInteger)i < length;
        uint8_t byte = readable ? bytes[i] : 0;
        BOOL highlighted = readable && far != 0 &&
                           address + (uint64_t)i >= far &&
                           address + (uint64_t)i < far + width;

        NSString *byteText = readable ? [NSString stringWithFormat:@"%02X ", byte] : @"?? ";
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        attributes[NSFontAttributeName] = font;
        attributes[NSForegroundColorAttributeName] = readable
            ? (highlighted ? highlightColor : normalColor)
            : disabledColor;
        if (highlighted) {
            attributes[NSBackgroundColorAttributeName] = highlightBackground;
        }
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:byteText
                                                                     attributes:attributes]];
    }

    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" |"
                                                                 attributes:@{
                                                                     NSFontAttributeName: font,
                                                                     NSForegroundColorAttributeName: disabledColor
                                                                 }]];

    for (NSInteger i = 0; i < kMemoryBytesPerRow; i++) {
        BOOL readable = (NSUInteger)i < length;
        uint8_t byte = readable ? bytes[i] : 0;
        BOOL highlighted = readable && far != 0 &&
                           address + (uint64_t)i >= far &&
                           address + (uint64_t)i < far + width;
        char character = (byte >= 32 && byte <= 126) ? (char)byte : '.';
        NSString *characterText = readable ? [NSString stringWithFormat:@"%c", character] : @"?";
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        attributes[NSFontAttributeName] = font;
        attributes[NSForegroundColorAttributeName] = readable
            ? (highlighted ? highlightColor : normalColor)
            : disabledColor;
        if (highlighted) {
            attributes[NSBackgroundColorAttributeName] = highlightBackground;
        }
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:characterText
                                                                     attributes:attributes]];
    }

    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"|"
                                                                 attributes:@{
                                                                     NSFontAttributeName: font,
                                                                     NSForegroundColorAttributeName: disabledColor
                                                                 }]];

    return text;
}

- (NSString *)protectionTextForAddress:(uint64_t)address {
    mach_vm_address_t regionAddress = address;
    mach_vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName = MACH_PORT_NULL;

    kern_return_t kr = mach_vm_region(mach_task_self(),
                                      &regionAddress,
                                      &regionSize,
                                      VM_REGION_BASIC_INFO_64,
                                      (vm_region_info_t)&info,
                                      &count,
                                      &objectName);
    if (objectName != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), objectName);
    }
    if (kr != KERN_SUCCESS) {
        return @"??";
    }

    NSMutableString *text = [NSMutableString string];
    [text appendString:(info.protection & VM_PROT_READ) ? @"r" : @"-"];
    [text appendString:(info.protection & VM_PROT_WRITE) ? @"w" : @"-"];
    [text appendString:(info.protection & VM_PROT_EXECUTE) ? @"x" : @"-"];
    return text;
}

- (BOOL)isExecutableAddress:(uint64_t)address {
    return [[self protectionTextForAddress:address] containsString:@"x"];
}

- (uint64_t)readPointerAtAddress:(uint64_t)address {
    uint64_t value = 0;
    mach_vm_size_t outsize = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                              (mach_vm_address_t)address,
                                              sizeof(value),
                                              (mach_vm_address_t)&value,
                                              &outsize);
    if (kr != KERN_SUCCESS || outsize != sizeof(value)) {
        return 0;
    }
    return value;
}

- (void)showMemoryActionsForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.memoryRows.count) {
        return;
    }
    NSDictionary *row = self.memoryRows[indexPath.row];
    uint64_t address = [row[@"address"] unsignedLongLongValue];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"0x%llX", address]
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"跟随指针"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        uint64_t pointer = [strongSelf readPointerAtAddress:address];
        if (pointer == 0) {
            [strongSelf showAlert:@"该地址为 0" message:@"无法跟随指针"];
            return;
        }
        [strongSelf pushDataAddress:pointer];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"反汇编此地址"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf pushCodeAddress:address];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制地址"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"0x%llX", address];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    if (sheet.popoverPresentationController) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Actions

- (void)modeChanged:(UISegmentedControl *)sender {
    self.mode = (SSHInspectorMode)sender.selectedSegmentIndex;
    [self updateTitle];
    [self.tableView reloadData];
}

- (void)backTapped {
    if (self.mode == SSHInspectorModeMemory) {
        if (self.dataHistory.count > 1) {
            [self.dataHistory removeLastObject];
            [self switchToMode:SSHInspectorModeMemory];
            return;
        }
    } else if (self.mode == SSHInspectorModeDisassembly) {
        if (self.codeHistory.count > 1) {
            [self.codeHistory removeLastObject];
            [self switchToMode:SSHInspectorModeDisassembly];
            return;
        }
    }

    if (self.codeHistory.count > 1) {
        [self.codeHistory removeLastObject];
        [self switchToMode:SSHInspectorModeDisassembly];
    } else if (self.dataHistory.count > 1) {
        [self.dataHistory removeLastObject];
        [self switchToMode:SSHInspectorModeMemory];
    }
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateTitle {
    if (self.mode == SSHInspectorModeDisassembly) {
        uint64_t address = [self currentCodeAddress];
        SSSymbol *symbol = [[SSSymbolicator shared] symbolForAddress:address];
        self.titleLabel.text = symbol.shortText ?: [NSString stringWithFormat:@"0x%llX", (unsigned long long)address];
    } else if (self.mode == SSHInspectorModeMemory) {
        uint64_t address = [self currentDataAddress];
        SSSymbol *symbol = [[SSSymbolicator shared] symbolForAddress:address];
        self.titleLabel.text = symbol.shortText ?: [NSString stringWithFormat:@"0x%llX", (unsigned long long)address];
    } else {
        self.titleLabel.text = @"命中现场";
    }

    BOOL canGoBack = NO;
    if (self.mode == SSHInspectorModeMemory) {
        canGoBack = self.dataHistory.count > 1;
    } else if (self.mode == SSHInspectorModeDisassembly) {
        canGoBack = self.codeHistory.count > 1;
    } else {
        canGoBack = self.codeHistory.count > 1 || self.dataHistory.count > 1;
    }
    self.backButton.hidden = !canGoBack;
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)breakpointTapped {
    uint64_t address = [self currentCodeAddress];
    if (address == 0) {
        return;
    }

    SSDebugger *debugger = [SSDebugger sharedInstance];
    if (!debugger.isDebugging && ![debugger startDebugWithPid:getpid()]) {
        [self showAlert:@"设置断点失败" message:@"调试器启动失败"];
        return;
    }

    BOOL success = [debugger setFunctionBreakpoint:address software:YES hitCount:0];
    if (success) {
        SSSymbol *symbol = [[SSSymbolicator shared] symbolForAddress:address];
        [self showAlert:@"已设置执行断点"
                message:[NSString stringWithFormat:@"0x%llX\n%@\n命中后会弹出寄存器/调用栈",
                         (unsigned long long)address,
                         symbol.shortText ?: @""]];
    } else {
        [self showAlert:@"设置断点失败"
                message:@"软件断点需要可写代码页；可以改在内存页用硬件断点"];
    }
}

- (void)copyTapped {
    uint64_t address = self.mode == SSHInspectorModeMemory ? [self currentDataAddress]
                                                           : [self currentCodeAddress];
    SSSymbol *symbol = [[SSSymbolicator shared] symbolForAddress:address];
    NSString *text = [NSString stringWithFormat:@"0x%llX  %@  %@",
                      (unsigned long long)address,
                      symbol.shortText ?: @"",
                      symbol.moduleText ?: @""];
    [UIPasteboard generalPasteboard].string = text;
    [self showAlert:@"已复制" message:text];
}

- (void)exportTapped {
    uint8_t size = self.hit.accessSize ?: 8;
    NSMutableString *report = [NSMutableString string];

    [report appendString:@"=== 访问命中 ===\n"];
    [report appendFormat:@"访问点: 0x%llX  [%@]  %uB\n",
     (unsigned long long)self.record.address, [self typeText], (unsigned)size];
    [report appendFormat:@"实际访问: 0x%llX\n", (unsigned long long)self.hit.memoryAddress];
    [report appendFormat:@"值: %@\n", [self hexValue:self.hit.value width:size]];
    [report appendFormat:@"线程: 0x%X\n", self.hit.threadId];

    SSSymbol *pcSymbol = [[SSSymbolicator shared] symbolForAddress:self.hit.instructionAddr];
    [report appendFormat:@"触发: 0x%llX  %@  %@\n",
     (unsigned long long)self.hit.instructionAddr,
     pcSymbol.shortText ?: @"",
     pcSymbol.moduleText ?: @""];

    DisassembledInstruction *instruction = [self instructionAtAddress:self.hit.instructionAddr];
    SSInstructionExplanation *explanation =
        [SSInstructionExplainer explainInstruction:instruction
                                               far:self.hit.memoryAddress
                                         registers:self.hit.registers
                                             width:size];
    if (explanation.summary.length > 0) {
        [report appendFormat:@"解释: %@\n", explanation.summary];
    }

    [report appendString:@"\n=== 调用栈 ===\n"];
    for (NSDictionary *frame in self.frameRows) {
        [report appendFormat:@"#%@  0x%llX  %@  %@\n",
         frame[@"index"],
         [frame[@"addressValue"] unsignedLongLongValue],
         frame[@"symbol"],
         frame[@"module"]];
    }

    [report appendString:@"\n=== 寄存器 ===\n"];
    for (NSDictionary *row in self.registerRows) {
        [report appendFormat:@"%@ = %@\n", row[@"name"], row[@"value"]];
    }

    [UIPasteboard generalPasteboard].string = report;
    [self showAlert:@"已导出" message:[NSString stringWithFormat:@"共 %lu 行，已复制到剪贴板",
                                       (unsigned long)[report componentsSeparatedByString:@"\n"].count]];
}

#pragma mark - Notification

- (void)handleSymbolsReady:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self buildStaticData];
        [self refreshSummary];
        self.builtCodeAddress = 0;
        self.builtDataAddress = 0;
        [self updateTitle];
        [self.tableView reloadData];
    });
}

- (void)handleRecordUpdate:(NSNotification *)notification {
    if (notification.object != self.record) {
        return;
    }
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
        [strongSelf refreshSummary];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.mode) {
        case SSHInspectorModeOverview:
            return (NSInteger)self.overviewRows.count;
        case SSHInspectorModeDisassembly:
            [self ensureDisassembly];
            return (NSInteger)self.disassemblyLines.count;
        case SSHInspectorModeCallStack:
            return (NSInteger)self.frameRows.count;
        case SSHInspectorModeRegisters:
            return (NSInteger)self.registerRows.count;
        case SSHInspectorModeMemory:
            [self ensureMemory];
            return (NSInteger)self.memoryRows.count;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.mode == SSHInspectorModeDisassembly) {
        [self ensureDisassembly];
        SSDisassemblyCell *cell = [tableView dequeueReusableCellWithIdentifier:[SSDisassemblyCell reuseIdentifier]
                                                                forIndexPath:indexPath];
        if (indexPath.row < (NSInteger)self.disassemblyLines.count) {
            [cell configureWithLine:self.disassemblyLines[indexPath.row]];
        }
        return cell;
    }

    if (self.mode == SSHInspectorModeMemory) {
        [self ensureMemory];
        static NSString *hexCellId = @"SSHexCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:hexCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:hexCellId];
            cell.backgroundColor = [UIColor clearColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.lineBreakMode = NSLineBreakByClipping;
        }
        if (indexPath.row < (NSInteger)self.memoryRows.count) {
            cell.textLabel.attributedText = [self hexTextForRow:self.memoryRows[indexPath.row]];
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (self.mode == SSHInspectorModeRegisters) {
        static NSString *registerCellId = @"SSRegisterCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:registerCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                          reuseIdentifier:registerCellId];
            cell.backgroundColor = [UIColor clearColor];
        }
        NSDictionary *row = self.registerRows[indexPath.row];
        cell.textLabel.text = row[@"name"];
        cell.textLabel.font = [AppTheme monospaceFont:12];
        cell.textLabel.textColor = [AppTheme textDisabledColor];
        cell.detailTextLabel.text = row[@"value"];
        cell.detailTextLabel.font = [AppTheme monospaceFont:12];
        cell.detailTextLabel.textColor = [AppTheme textColor];

        BOOL hasValue = [row[@"hasValue"] boolValue];
        uint64_t value = [row[@"addressValue"] unsignedLongLongValue];
        BOOL tappable = hasValue && value >= 0x1000;
        cell.accessoryType = tappable ? UITableViewCellAccessoryDisclosureIndicator
                                      : UITableViewCellAccessoryNone;
        cell.selectionStyle = tappable ? UITableViewCellSelectionStyleDefault
                                       : UITableViewCellSelectionStyleNone;
        return cell;
    }

    static NSString *subtitleCellId = @"SSSubtitleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:subtitleCellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:subtitleCellId];
        cell.backgroundColor = [UIColor clearColor];
    }

    cell.textLabel.font = [AppTheme regularFont:11];
    cell.textLabel.textColor = [AppTheme textDisabledColor];
    cell.detailTextLabel.font = [AppTheme monospaceFont:13];
    cell.detailTextLabel.textColor = [AppTheme textColor];

    if (self.mode == SSHInspectorModeOverview) {
        NSDictionary *row = self.overviewRows[indexPath.row];
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = row[@"value"];
        NSString *action = row[@"action"];
        cell.accessoryType = action.length > 0 ? UITableViewCellAccessoryDisclosureIndicator
                                               : UITableViewCellAccessoryNone;
        cell.selectionStyle = action.length > 0 ? UITableViewCellSelectionStyleDefault
                                                : UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *row = self.frameRows[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"#%@   %@", row[@"index"], row[@"address"]];
        NSString *symbolText = row[@"symbol"];
        NSString *moduleText = row[@"module"];
        if (symbolText.length > 0) {
            cell.detailTextLabel.text = moduleText.length > 0
                ? [NSString stringWithFormat:@"%@  ·  %@", symbolText, moduleText]
                : symbolText;
        } else {
            cell.detailTextLabel.text = moduleText;
        }
        cell.accessoryType = indexPath.row > 0 ? UITableViewCellAccessoryDisclosureIndicator
                                               : UITableViewCellAccessoryNone;
        cell.selectionStyle = indexPath.row > 0 ? UITableViewCellSelectionStyleDefault
                                                : UITableViewCellSelectionStyleNone;
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (self.mode) {
        case SSHInspectorModeDisassembly:
            return @"点带 › 的分支行跟进；顶部「返回」回退";
        case SSHInspectorModeCallStack:
            return @"#0 = 触发访问的函数，#1 = 调用者；点帧跳到对应地址";
        case SSHInspectorModeRegisters:
            return @"点值：可执行地址进反汇编，否则进内存";
        case SSHInspectorModeMemory: {
            uint64_t address = [self currentDataAddress];
            SSSymbol *symbol = [[SSSymbolicator shared] symbolForAddress:address];
            return [NSString stringWithFormat:@"0x%llX  %@  [%@]",
                    (unsigned long long)address,
                    symbol.shortText ?: @"",
                    [self protectionTextForAddress:address]];
        }
        default:
            return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (self.mode) {
        case SSHInspectorModeDisassembly: {
            [self ensureDisassembly];
            if (indexPath.row < (NSInteger)self.disassemblyLines.count) {
                SSDisassemblyLine *line = self.disassemblyLines[indexPath.row];
                return line.annotation.length > 0 ? 42 : 30;
            }
            return 30;
        }
        case SSHInspectorModeCallStack:
            return 46;
        case SSHInspectorModeRegisters:
            return 34;
        case SSHInspectorModeMemory:
            return 24;
        default:
            return 44;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.mode == SSHInspectorModeDisassembly) {
        [self ensureDisassembly];
        if (indexPath.row < (NSInteger)self.disassemblyLines.count) {
            SSDisassemblyLine *line = self.disassemblyLines[indexPath.row];
            if (line.isBranch && line.branchTarget != 0) {
                [self pushCodeAddress:line.branchTarget];
            }
        }
        return;
    }

    if (self.mode == SSHInspectorModeCallStack) {
        if (indexPath.row < (NSInteger)self.frameRows.count) {
            uint64_t address = [self.frameRows[indexPath.row][@"addressValue"] unsignedLongLongValue];
            if (indexPath.row > 0 && address >= 4) {
                address -= 4;   // 返回地址指向调用指令的下一条
            }
            [self pushCodeAddress:address];
        }
        return;
    }

    if (self.mode == SSHInspectorModeRegisters) {
        if (indexPath.row < (NSInteger)self.registerRows.count) {
            NSDictionary *row = self.registerRows[indexPath.row];
            if (![row[@"hasValue"] boolValue]) {
                return;
            }
            uint64_t value = [row[@"addressValue"] unsignedLongLongValue];
            if (value < 0x1000) {
                return;
            }
            if ([self isExecutableAddress:value]) {
                [self pushCodeAddress:value];
            } else {
                [self pushDataAddress:value];
            }
        }
        return;
    }

    if (self.mode == SSHInspectorModeMemory) {
        [self showMemoryActionsForIndexPath:indexPath];
        return;
    }

    if (self.mode == SSHInspectorModeOverview) {
        if (indexPath.row >= (NSInteger)self.overviewRows.count) {
            return;
        }
        NSDictionary *row = self.overviewRows[indexPath.row];
        NSString *action = row[@"action"];
        uint64_t address = [row[@"addressValue"] unsignedLongLongValue];
        if ([action isEqualToString:@"data"]) {
            [self pushDataAddress:address];
        } else if ([action isEqualToString:@"code"]) {
            [self pushCodeAddress:address];
        } else if ([action isEqualToString:@"callstack"]) {
            [self switchToMode:SSHInspectorModeCallStack];
        }
    }
}

@end
