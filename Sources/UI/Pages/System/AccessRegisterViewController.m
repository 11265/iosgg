#import "UI/Pages/System/AccessRegisterViewController.h"
#import "UI/Components/ThemeConfig.h"
#import <mach-o/dyld.h>
#import "Modules/ProcessInfo/ProcessMemory.h"
#import "Modules/MemoryAnalysis/ARM64Assembler.h"
#import "Services/LogService.h"
#import "Modules/Debugger/SSDebugger.h"
#import "Services/SSSymbolicator.h"

@interface AccessRegisterViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *hexButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, assign) BOOL showHex;
@property (nonatomic, strong) NSArray *registerData;
@property (nonatomic, strong) NSArray *callStackData;
@property (nonatomic, strong) NSMutableArray *moduleRanges;
@property (nonatomic, strong) NSArray *assemblyData;
@property (nonatomic, strong) UIView *symbolBar;
@property (nonatomic, strong) UILabel *symbolLabel;
@property (nonatomic, strong) UILabel *symbolDetailLabel;

@end

static NSArray *RegisterNames = nil;
static dispatch_once_t onceToken;

@implementation AccessRegisterViewController

typedef NS_ENUM(NSInteger, SSRegisterSectionKind) {
    SSRegisterSectionKindNone = -1,
    SSRegisterSectionKindAssembly = 0,
    SSRegisterSectionKindRegisters,
    SSRegisterSectionKindCallStack
};

- (SSRegisterSectionKind)sectionKindForIndex:(NSInteger)section {
    NSInteger index = section;
    if (self.assemblyData.count > 0) {
        if (index == 0) return SSRegisterSectionKindAssembly;
        index--;
    }
    if (self.registerData.count > 0) {
        if (index == 0) return SSRegisterSectionKindRegisters;
        index--;
    }
    if (self.callStackData.count > 0) {
        if (index == 0) return SSRegisterSectionKindCallStack;
    }
    return SSRegisterSectionKindNone;
}

+ (void)initialize {
    dispatch_once(&onceToken, ^{
        RegisterNames = @[@"x0", @"x1", @"x2", @"x3", @"x4", @"x5", @"x6", @"x7",
                          @"x8", @"x9", @"x10", @"x11", @"x12", @"x13", @"x14", @"x15",
                          @"x16", @"x17", @"x18", @"x19", @"x20", @"x21", @"x22", @"x23",
                          @"x24", @"x25", @"x26", @"x27", @"x28", @"fp", @"lr", @"sp", @"pc", @"cpsr"];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    self.showHex = YES;
    
    [self loadModuleRanges];
    [self buildData];
    [self setupNavigationBar];
    [self setupSymbolBar];
    [self setupTableView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSymbolsReady:)
                                                 name:SSSymbolicatorObjCMethodsDidBecomeReadyNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleSymbolsReady:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshSymbolBar];
        [self buildData];
        [self.tableView reloadData];
    });
}

- (void)setupNavigationBar {
    UIView *navBar = [[UIView alloc] init];
    navBar.backgroundColor = [UIColor whiteColor];
    navBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:navBar];
    
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [backButton setTitle:@"< 调试" forState:UIControlStateNormal];
    [backButton setTitleColor:[UIColor colorWithRed:0.0f green:0.48f blue:1.0f alpha:1.0f] forState:UIControlStateNormal];
    backButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [backButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:backButton];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = [NSString stringWithFormat:@"0x%llX", self.instructionAddr];
    titleLabel.textColor = [UIColor blackColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:titleLabel];
    
    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exportButton setTitle:@"复制" forState:UIControlStateNormal];
    [self.exportButton setTitleColor:[UIColor colorWithRed:0.0f green:0.48f blue:1.0f alpha:1.0f] forState:UIControlStateNormal];
    self.exportButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [self.exportButton addTarget:self action:@selector(exportButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.exportButton];
    
    self.hexButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.hexButton setTitle:@"HEX" forState:UIControlStateNormal];
    [self.hexButton setTitleColor:[UIColor colorWithRed:0.0f green:0.48f blue:1.0f alpha:1.0f] forState:UIControlStateNormal];
    self.hexButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [self.hexButton addTarget:self action:@selector(hexButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.hexButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.hexButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [navBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [navBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [navBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [navBar.heightAnchor constraintEqualToConstant:44],
        
        [backButton.leadingAnchor constraintEqualToAnchor:navBar.leadingAnchor constant:10],
        [backButton.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor],
        
        [titleLabel.centerXAnchor constraintEqualToAnchor:navBar.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor],
        
        [self.hexButton.trailingAnchor constraintEqualToAnchor:navBar.trailingAnchor constant:-10],
        [self.hexButton.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor],
        
        [self.exportButton.trailingAnchor constraintEqualToAnchor:self.hexButton.leadingAnchor constant:-10],
        [self.exportButton.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]
    ]];
    
    if (self.showsResumeControls) {
        [self setupResumeButtonInNavBar:navBar afterView:backButton];
    }
}

- (void)setupResumeButtonInNavBar:(UIView *)navBar afterView:(UIView *)anchorView {
    UIButton *resumeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resumeButton setTitle:@"继续" forState:UIControlStateNormal];
    [resumeButton setTitleColor:[UIColor colorWithRed:0.90f green:0.25f blue:0.20f alpha:1.0f]
                       forState:UIControlStateNormal];
    resumeButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [resumeButton addTarget:self
                     action:@selector(resumeTapped)
           forControlEvents:UIControlEventTouchUpInside];
    resumeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:resumeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [resumeButton.leadingAnchor constraintEqualToAnchor:anchorView.trailingAnchor constant:12],
        [resumeButton.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]
    ]];
}

- (void)resumeTapped {
    self.showsResumeControls = NO;  // 防止 viewWillDisappear 里重复继续
    [[SSDebugger sharedInstance] continueStoppedThread];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // 断点把线程停住了，页面一旦消失就必须放行，否则游戏会一直被冻住
    if (self.showsResumeControls) {
        self.showsResumeControls = NO;
        [[SSDebugger sharedInstance] continueStoppedThread];
        [LoggingService log:@"[断点] 寄存器页关闭，已自动继续被断住的线程"];
    }
}

- (void)setupSymbolBar {
    self.symbolBar = [[UIView alloc] init];
    self.symbolBar.backgroundColor = [UIColor colorWithWhite:0.96f alpha:1.0f];
    self.symbolBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.symbolBar];
    
    self.symbolLabel = [[UILabel alloc] init];
    self.symbolLabel.textColor = [UIColor blackColor];
    self.symbolLabel.font = [UIFont boldSystemFontOfSize:13];
    self.symbolLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.symbolLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.symbolBar addSubview:self.symbolLabel];
    
    self.symbolDetailLabel = [[UILabel alloc] init];
    self.symbolDetailLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
    self.symbolDetailLabel.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    self.symbolDetailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.symbolDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.symbolBar addSubview:self.symbolDetailLabel];
    
    [self refreshSymbolBar];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.symbolBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:44],
        [self.symbolBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.symbolBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.symbolBar.heightAnchor constraintEqualToConstant:44],
        
        [self.symbolLabel.topAnchor constraintEqualToAnchor:self.symbolBar.topAnchor constant:4],
        [self.symbolLabel.leadingAnchor constraintEqualToAnchor:self.symbolBar.leadingAnchor],
        [self.symbolLabel.trailingAnchor constraintEqualToAnchor:self.symbolBar.trailingAnchor],
        
        [self.symbolDetailLabel.topAnchor constraintEqualToAnchor:self.symbolLabel.bottomAnchor constant:2],
        [self.symbolDetailLabel.leadingAnchor constraintEqualToAnchor:self.symbolBar.leadingAnchor],
        [self.symbolDetailLabel.trailingAnchor constraintEqualToAnchor:self.symbolBar.trailingAnchor]
    ]];
}

- (void)refreshSymbolBar {
    if (!self.symbolLabel || !self.symbolDetailLabel) {
        return;
    }
    SSSymbol *symbol = self.instructionAddr != 0
        ? [[SSSymbolicator shared] symbolForAddress:self.instructionAddr]
        : nil;
    self.symbolLabel.text = symbol.shortText ?: @"未知地址";
    if (symbol.moduleText.length > 0) {
        self.symbolDetailLabel.text = [NSString stringWithFormat:@"触发点 · %@", symbol.moduleText];
    } else {
        self.symbolDetailLabel.text = @"触发点";
    }
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor whiteColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.tableView addGestureRecognizer:longPress];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.symbolBar.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)loadModuleRanges {
    self.moduleRanges = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!header) continue;
        
        uint64_t slide = _dyld_get_image_vmaddr_slide(i);
        uint64_t min_addr = UINT64_MAX;
        uint64_t max_addr = 0;
        
        struct load_command *lc = (struct load_command *)(header + 1);
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if (lc->cmd == LC_SEGMENT_64) {
                struct segment_command_64 *seg = (struct segment_command_64 *)lc;
                // __PAGEZERO（initprot=0）从 0 开始，算进来会让「地址归属」把所有低地址都判给主二进制
                BOOL usable = (seg->vmsize > 0) &&
                              ((seg->initprot & (VM_PROT_READ | VM_PROT_EXECUTE)) != 0);
                if (usable) {
                    uint64_t start = seg->vmaddr + slide;
                    uint64_t end = start + seg->vmsize;
                    if (start < min_addr) min_addr = start;
                    if (end > max_addr) max_addr = end;
                }
            }
            if (lc->cmdsize == 0) break;
            lc = (struct load_command *)((uintptr_t)lc + lc->cmdsize);
        }
        
        if (min_addr < max_addr) {
            const char *name = _dyld_get_image_name(i);
            NSString *moduleName = [NSString stringWithUTF8String:name].lastPathComponent;
            
            [self.moduleRanges addObject:@{
                @"start": @(min_addr),
                @"end": @(max_addr),
                @"name": moduleName
            }];
        }
    }
}

- (NSDictionary *)analyzeAddress:(uint64_t)address {
    for (NSDictionary *range in self.moduleRanges) {
        uint64_t start = [range[@"start"] unsignedLongLongValue];
        uint64_t end = [range[@"end"] unsignedLongLongValue];
        
        if (address >= start && address < end) {
            uint64_t offset = address - start;
            return @{
                @"isStatic": @YES,
                @"moduleName": range[@"name"],
                @"offset": @(offset)
            };
        }
    }
    return @{@"isStatic": @NO};
}

- (void)buildData {
    NSMutableArray *regs = [NSMutableArray array];
    
    for (int i = 0; i < RegisterNames.count; i++) {
        NSString *name = RegisterNames[i];
        NSNumber *val = self.registers[name];
        uint64_t value = val ? val.unsignedLongLongValue : 0;
        
        [regs addObject:@{
            @"name": name,
            @"value": @(value),
            @"hasValue": val ? @YES : @NO
        }];
    }
    self.registerData = regs;
    
    NSMutableArray *stack = [NSMutableArray array];
    if (self.callStack) {
        for (int i = 0; i < self.callStack.count; i++) {
            NSString *addrStr = self.callStack[i];
            uint64_t addr = strtoull([addrStr UTF8String], NULL, 16);
            NSDictionary *addrInfo = [self analyzeAddress:addr];
            
            // 前 12 帧做完整符号化（会按镜像解析符号表），更深的帧只给「模块+偏移」，
            // 避免一次打开页面时把几十个系统库的符号表全解析一遍。
            NSString *symbolText = @"";
            NSString *moduleText = @"";
            if (i < 12) {
                SSSymbol *symbol = (i == 0)
                    ? [[SSSymbolicator shared] symbolForAddress:addr]
                    : [[SSSymbolicator shared] symbolForReturnAddress:addr];
                symbolText = symbol.shortText ?: @"";
                moduleText = symbol.moduleText ?: @"";
            } else {
                NSString *moduleName = addrInfo[@"moduleName"];
                uint64_t offset = [addrInfo[@"offset"] unsignedLongLongValue];
                if (moduleName.length > 0) {
                    moduleText = [NSString stringWithFormat:@"%@+0x%llX", moduleName, offset];
                } else {
                    moduleText = [NSString stringWithFormat:@"0x%llX", addr];
                }
            }
            
            [stack addObject:@{
                @"index": @(i),
                @"address": addrStr,
                @"addrValue": @(addr),
                @"addrInfo": addrInfo,
                @"symbolText": symbolText,
                @"moduleText": moduleText
            }];
        }
    }
    self.callStackData = stack;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self buildAssemblyData];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    });
}

- (void)buildAssemblyData {
    if (self.instructionAddr == 0) {
        self.assemblyData = @[];
        return;
    }
    
    NSMutableArray *asmList = [NSMutableArray array];
    
    int contextLines = 10;
    uint64_t startAddr = self.instructionAddr - (contextLines * 4);
    uint64_t currentAddr = startAddr;
    
    for (int i = 0; i < contextLines * 2 + 1; i++) {
        @try {
            uint32_t instruction = 0;
            mach_vm_size_t size = sizeof(uint32_t);
            mach_vm_size_t outsize;
            
            kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                                       currentAddr,
                                                       size,
                                                       (mach_vm_address_t)&instruction,
                                                       &outsize);
            
            NSString *asmStr;
            BOOL isCurrentLine = (currentAddr == self.instructionAddr);
            
            if (kr == KERN_SUCCESS) {
                @try {
                    DisassembledInstruction *disasm = [ARM64Assembler disassemble:instruction atAddress:currentAddr];
                    if (disasm) {
                        asmStr = [NSString stringWithFormat:@"%@ %@", disasm.mnemonic ?: @"?", disasm.opStr ?: @""];
                    } else {
                        asmStr = @"(反汇编失败)";
                    }
                } @catch (NSException *exception) {
                    asmStr = @"(反汇编失败)";
                }
            } else {
                asmStr = @"(无法读取)";
            }
            
            [asmList addObject:@{
                @"address": @(currentAddr),
                @"assembly": asmStr,
                @"isCurrentLine": @(isCurrentLine)
            }];
            
        } @catch (NSException *exception) {
            [asmList addObject:@{
                @"address": @(currentAddr),
                @"assembly": @"(处理异常)",
                @"isCurrentLine": @(NO)
            }];
        }
        
        currentAddr += 4;
    }
    
    self.assemblyData = asmList;
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)hexButtonTapped {
    self.showHex = !self.showHex;
    [self.hexButton setTitle:self.showHex ? @"HEX" : @"DEC" forState:UIControlStateNormal];
    [self.tableView reloadData];
}

- (void)exportButtonTapped {
    NSMutableString *allContent = [NSMutableString string];
    
    [allContent appendString:@"=== 汇编代码 ===\n"];
    for (NSDictionary *asmData in self.assemblyData) {
        uint64_t addr = [asmData[@"address"] unsignedLongLongValue];
        NSString *assembly = asmData[@"assembly"];
        BOOL isCurrentLine = [asmData[@"isCurrentLine"] boolValue];
        NSString *marker = isCurrentLine ? @" <-- " : @"";
        [allContent appendFormat:@"0x%llX: %@%@\n", addr, assembly, marker];
    }
    
    [allContent appendString:@"\n=== 寄存器 ===\n"];
    for (NSDictionary *reg in self.registerData) {
        NSString *name = reg[@"name"];
        uint64_t value = [reg[@"value"] unsignedLongLongValue];
        BOOL hasValue = [reg[@"hasValue"] boolValue];
        
        if (hasValue) {
            if (self.showHex) {
                [allContent appendFormat:@"%@: 0x%llX\n", name, value];
            } else {
                [allContent appendFormat:@"%@: %llu\n", name, value];
            }
        } else {
            [allContent appendFormat:@"%@: --\n", name];
        }
    }
    
    UIPasteboard.generalPasteboard.string = allContent;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                   message:[NSString stringWithFormat:@"共 %ld 行内容", (long)(self.assemblyData.count + self.registerData.count)]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [gesture locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
        
        if (indexPath) {
            NSString *copyText = [self getTextForRowAtIndexPath:indexPath];
            if (copyText) {
                UIPasteboard.generalPasteboard.string = copyText;
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                               message:copyText
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    }
}

- (NSString *)getTextForRowAtIndexPath:(NSIndexPath *)indexPath {
    SSRegisterSectionKind kind = [self sectionKindForIndex:indexPath.section];
    if (kind == SSRegisterSectionKindAssembly && indexPath.row < self.assemblyData.count) {
        NSDictionary *asmData = self.assemblyData[indexPath.row];
        uint64_t addr = [asmData[@"address"] unsignedLongLongValue];
        NSString *assembly = asmData[@"assembly"];
        return [NSString stringWithFormat:@"0x%llX: %@", addr, assembly];
    }
    
    if (kind == SSRegisterSectionKindRegisters && indexPath.row < self.registerData.count) {
        NSDictionary *reg = self.registerData[indexPath.row];
        NSString *name = reg[@"name"];
        uint64_t value = [reg[@"value"] unsignedLongLongValue];
        BOOL hasValue = [reg[@"hasValue"] boolValue];
        
        if (hasValue) {
            if (self.showHex) {
                return [NSString stringWithFormat:@"%@: 0x%llX", name, value];
            } else {
                return [NSString stringWithFormat:@"%@: %llu", name, value];
            }
        }
        return [NSString stringWithFormat:@"%@: --", name];
    }
    
    if (kind == SSRegisterSectionKindCallStack && indexPath.row < self.callStackData.count) {
        NSDictionary *frame = self.callStackData[indexPath.row];
        return [NSString stringWithFormat:@"#%@  %@  %@",
                frame[@"index"], frame[@"address"], frame[@"symbolText"]];
    }
    
    return nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = 0;
    if (self.assemblyData.count > 0) sections++;
    if (self.registerData.count > 0) sections++;
    if (self.callStackData.count > 0) sections++;
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self sectionKindForIndex:section]) {
        case SSRegisterSectionKindAssembly:
            return self.assemblyData.count;
        case SSRegisterSectionKindRegisters:
            return self.registerData.count;
        case SSRegisterSectionKindCallStack:
            return self.callStackData.count;
        default:
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *asmCellId = @"AsmCell";
    static NSString *regCellId = @"RegCell";
    static NSString *stackCellId = @"StackCell";
    
    SSRegisterSectionKind kind = [self sectionKindForIndex:indexPath.section];
    
    if (kind == SSRegisterSectionKindCallStack) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:stackCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:stackCellId];
            cell.backgroundColor = [UIColor whiteColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:12];
            cell.textLabel.textColor = [UIColor blackColor];
            cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10];
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
        }
        
        NSDictionary *frame = self.callStackData[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"#%@  %@", frame[@"index"], frame[@"address"]];
        NSString *symbolText = frame[@"symbolText"];
        NSString *moduleText = frame[@"moduleText"];
        if (symbolText.length > 0) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@", symbolText, moduleText];
        } else {
            cell.detailTextLabel.text = moduleText;
        }
        return cell;
    }
    
    if (kind == SSRegisterSectionKindAssembly) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:asmCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:asmCellId];
            cell.backgroundColor = [UIColor whiteColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        
        NSDictionary *asmData = self.assemblyData[indexPath.row];
        uint64_t addr = [asmData[@"address"] unsignedLongLongValue];
        NSString *assembly = asmData[@"assembly"];
        BOOL isCurrentLine = [asmData[@"isCurrentLine"] boolValue];
        
        NSString *addrStr = [NSString stringWithFormat:@"0x%011llX", addr];
        
        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] init];
        
        NSAttributedString *addrPart = [[NSAttributedString alloc] initWithString:addrStr
                                                                       attributes:@{NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:14],
                                                                                    NSForegroundColorAttributeName: [UIColor colorWithWhite:0.5f alpha:1.0f]}];
        [attrStr appendAttributedString:addrPart];
        
        NSAttributedString *spacePart = [[NSAttributedString alloc] initWithString:@"    "
                                                                        attributes:@{NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:14]}];
        [attrStr appendAttributedString:spacePart];
        
        NSAttributedString *asmPart = [[NSAttributedString alloc] initWithString:assembly
                                                                      attributes:@{NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:14],
                                                                                   NSForegroundColorAttributeName: isCurrentLine ?
                                                                                       [UIColor colorWithRed:1.0f green:0.3f blue:0.3f alpha:1.0f] :
                                                                                       [UIColor blackColor]}];
        [attrStr appendAttributedString:asmPart];
        
        cell.textLabel.attributedText = attrStr;
        cell.backgroundColor = [UIColor whiteColor];
        
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:regCellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:regCellId];
        cell.backgroundColor = [UIColor whiteColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UILabel *nameLabel = [[UILabel alloc] init];
        nameLabel.tag = 100;
        nameLabel.font = [UIFont fontWithName:@"Menlo" size:14];
        nameLabel.textColor = [UIColor blackColor];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:nameLabel];
        
        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.tag = 101;
        valueLabel.font = [UIFont fontWithName:@"Menlo" size:14];
        valueLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.0f];
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:valueLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [nameLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:15],
            [nameLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            
            [valueLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
            [valueLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:nameLabel.trailingAnchor constant:20]
        ]];
    }
    
    UILabel *nameLabel = (UILabel *)[cell.contentView viewWithTag:100];
    UILabel *valueLabel = (UILabel *)[cell.contentView viewWithTag:101];
    
    NSDictionary *reg = self.registerData[indexPath.row];
    NSString *name = reg[@"name"];
    uint64_t value = [reg[@"value"] unsignedLongLongValue];
    BOOL hasValue = [reg[@"hasValue"] boolValue];
    
    nameLabel.text = name;
    
    if (hasValue) {
        if (self.showHex) {
            valueLabel.text = [NSString stringWithFormat:@"0x%llX", value];
        } else {
            valueLabel.text = [NSString stringWithFormat:@"%llu", value];
        }
    } else {
        valueLabel.text = @"--";
    }
    
    return cell;
}

- (NSString *)getPaddingForRegister:(NSString *)regName {
    if (regName.length >= 3) {
        return @"";
    }
    return @" ";
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self sectionKindForIndex:section]) {
        case SSRegisterSectionKindAssembly:
            return @"汇编";
        case SSRegisterSectionKindRegisters:
            return @"寄存器";
        case SSRegisterSectionKindCallStack:
            return [NSString stringWithFormat:@"调用栈（%lu 帧）", (unsigned long)self.callStackData.count];
        default:
            return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self sectionKindForIndex:indexPath.section] == SSRegisterSectionKindCallStack) {
        return 44;
    }
    return 30;
}

@end
