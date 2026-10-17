#import "UI/Pages/System/AccessRegisterViewController.h"
#import "UI/Components/ThemeConfig.h"
#import <mach-o/dyld.h>
#import "Modules/ProcessInfo/ProcessMemory.h"
#import "Modules/MemoryAnalysis/ARM64Assembler.h"
#import "Services/LogService.h"
#import "Modules/Debugger/SSDebugger.h"

@interface AccessRegisterViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *hexButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, assign) BOOL showHex;
@property (nonatomic, strong) NSArray *registerData;
@property (nonatomic, strong) NSArray *callStackData;
@property (nonatomic, strong) NSMutableArray *moduleRanges;
@property (nonatomic, strong) NSArray *assemblyData;

@end

static NSArray *RegisterNames = nil;
static dispatch_once_t onceToken;

@implementation AccessRegisterViewController

+ (void)initialize {
    dispatch_once(&onceToken, ^{
        RegisterNames = @[@"x0", @"x1", @"x2", @"x3", @"x4", @"x5", @"x6", @"x7",
                          @"x8", @"x9", @"x10", @"x11", @"x12", @"x13", @"x14", @"x15",
                          @"x16", @"x17", @"x18", @"x19", @"x20", @"x21", @"x22", @"x23",
                          @"x24", @"x25", @"x26", @"x27", @"x28", @"fp", @"lr", @"sp", @"pc"];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    self.showHex = YES;
    
    [self loadModuleRanges];
    [self buildData];
    [self setupNavigationBar];
    [self setupTableView];
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
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:44],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
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
                uint64_t start = seg->vmaddr + slide;
                uint64_t end = start + seg->vmsize;
                if (start < min_addr) min_addr = start;
                if (end > max_addr) max_addr = end;
            }
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
            
            [stack addObject:@{
                @"index": @(i),
                @"address": addrStr,
                @"addrValue": @(addr),
                @"addrInfo": addrInfo
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
    if (self.assemblyData.count > 0 && indexPath.section == 0) {
        NSDictionary *asmData = self.assemblyData[indexPath.row];
        uint64_t addr = [asmData[@"address"] unsignedLongLongValue];
        NSString *assembly = asmData[@"assembly"];
        return [NSString stringWithFormat:@"0x%llX: %@", addr, assembly];
    }
    
    if (self.registerData.count > 0 && indexPath.section == (self.assemblyData.count > 0 ? 1 : 0)) {
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
    
    return nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = 0;
    if (self.assemblyData.count > 0) sections++;
    if (self.registerData.count > 0) sections++;
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 && self.assemblyData.count > 0) {
        return self.assemblyData.count;
    }
    if (self.registerData.count > 0) {
        return self.registerData.count;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *asmCellId = @"AsmCell";
    static NSString *regCellId = @"RegCell";
    
    if (self.assemblyData.count > 0 && indexPath.section == 0) {
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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 30;
}

@end
