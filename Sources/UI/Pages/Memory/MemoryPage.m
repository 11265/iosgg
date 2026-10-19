#import "UI/Pages/Memory/MemoryPage.h"
#import "UI/Pages/Memory/MemoryPage+Private.h"
#import "UI/Pages/Memory/MemoryPage+Batch.h"
#import "UI/Components/FloatingWindow.h"
#import "Modules/Disassembly/InstructionBrowser.h"
#import "Services/LogService.h"
#import "Modules/Disassembly/ARM64Assembler.h"
#import "UI/Pages/Record/RecordPage.h"

#import "UI/Components/ThemeConfig.h"
#import "UI/Components/MemoryCell.h"
#import "Models/DisplayItem.h"
#import "UI/Pages/Memory/MemoryPage+AssemblyActions.h"

@implementation MemoryPages

- (void)viewDidLoad {
    [super viewDidLoad];
    [LoggingService log:@"内存页面: viewDidLoad 开始"];
    
    self.view.backgroundColor = IMGUI_BG_COLOR;
    
    // 初始化特征码长度为12字节
    self.patternLength = 12;
    
    // 1. Header (Title Bar) - Removed
    // UIView *headerView = [[UIView alloc] init];
    // ... (Removed header code)

    // 2. Control Panel
    UIView *controlPanel = [[UIView alloc] init];
    controlPanel.backgroundColor = IMGUI_CHILD_BG;
    controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controlPanel];

    // Row 1: Address Input & Jump
    UILabel *addrLabel = [[UILabel alloc] init];
    addrLabel.text = @"地址:";
    addrLabel.font = ImGuiFont(13, NO);
    addrLabel.textColor = IMGUI_TEXT;
    addrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:addrLabel];

    self.inputTextField = [[UITextField alloc] init];
    self.inputTextField.placeholder = @"输入地址...";
    self.inputTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"输入地址..." attributes:@{NSForegroundColorAttributeName: IMGUI_TEXT_DISABLED}];
    self.inputTextField.backgroundColor = IMGUI_FRAME_BG;
    self.inputTextField.textColor = IMGUI_TEXT;
    self.inputTextField.font = [UIFont fontWithName:@"Menlo" size:13];
    self.inputTextField.layer.cornerRadius = 2;
    self.inputTextField.textAlignment = NSTextAlignmentLeft;
    self.inputTextField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 0)];
    self.inputTextField.leftViewMode = UITextFieldViewModeAlways;
    self.inputTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.inputTextField];

    UIButton *jumpButton = [self createCyberButtonWithTitle:@"跳转" action:@selector(jumpButtonTapped:)];
    [controlPanel addSubview:jumpButton];
    
    UIButton *clearButton = [self createCyberButtonWithTitle:@"清除" action:@selector(clearButtonTapped:)];
    [controlPanel addSubview:clearButton];

    self.exportAllButton = [self createCyberButtonWithTitle:@"全复" action:@selector(exportAllButtonTapped)];
    [controlPanel addSubview:self.exportAllButton];

    UIButton *closeButton = [self createCyberButtonWithTitle:@"关闭" action:@selector(closeButtonTapped)];
    [controlPanel addSubview:closeButton];

    // Row 2: Type Selectors
    self.dataTypeContainer = [[UIView alloc] init];
    self.dataTypeContainer.backgroundColor = [UIColor clearColor];
    self.dataTypeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.dataTypeContainer];
    
    self.typeButtons = [NSMutableArray array];
    NSArray *types = @[@"I32", @"I64", @"F32", @"F64", @"汇编"];
    CGFloat btnSpacing = 4;
    
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *button = [self createCyberButtonWithTitle:types[i] action:@selector(typeButtonTapped:)];
        button.tag = i;
        button.titleLabel.font = ImGuiFont(12, NO);
        [self.dataTypeContainer addSubview:button];
        [self.typeButtons addObject:button];
    }
    
    // Row 3: Mode Toggle & Actions
    self.toggleModeButton = [self createCyberButtonWithTitle:@"多选模式: 关" action:@selector(modeButtonTapped:)];
    [controlPanel addSubview:self.toggleModeButton];
    
    self.selectionCountLabel = [[UILabel alloc] init];
    self.selectionCountLabel.textColor = IMGUI_TEXT; // Changed from white
    self.selectionCountLabel.font = ImGuiFont(12, NO);
    self.selectionCountLabel.text = @"0";
    self.selectionCountLabel.hidden = YES;
    self.selectionCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.selectionCountLabel];
    
    // Edit Buttons (Save, Copy, Cancel Selection)
    UIButton *saveButton = [self createCyberButtonWithTitle:@"保存" action:@selector(saveButtonTapped)];
    saveButton.backgroundColor = [UIColor colorWithRed:0.8f green:0.4f blue:0.0f alpha:0.6f]; // Orange-ish
    saveButton.hidden = YES;
    [controlPanel addSubview:saveButton];
    
    UIButton *copyButton = [self createCyberButtonWithTitle:@"复制" action:@selector(copySelectionTapped)];
    copyButton.backgroundColor = [UIColor colorWithRed:0.2f green:0.6f blue:0.8f alpha:0.6f]; // Blue-ish
    copyButton.hidden = YES;
    [controlPanel addSubview:copyButton];
    
    UIButton *cancelSelButton = [self createCyberButtonWithTitle:@"取消" action:@selector(cancelSelectionTapped)];
    cancelSelButton.hidden = YES;
    [controlPanel addSubview:cancelSelButton];
    
    self.editModeButtons = @[saveButton, copyButton, cancelSelButton];
    self.searchModeButtons = @[self.inputTextField, jumpButton, clearButton, self.dataTypeContainer]; // Update logic later
    
    // 3. TableView
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = IMGUI_CHILD_BG;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.layer.borderColor = IMGUI_BORDER_COLOR.CGColor;
    self.tableView.layer.borderWidth = 1.0;
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.tableView registerClass:[MemoryCell class] forCellReuseIdentifier:@"MemoryCell"];
    
    self.baseAddress = 0x100000000;
    
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    
    // --- Layout Constraints ---
    [NSLayoutConstraint activateConstraints:@[
        // Control Panel (Moved to top since Header is removed)
        [controlPanel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:5],
        [controlPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:5],
        [controlPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-5],
        [controlPanel.heightAnchor constraintEqualToConstant:95], // Adjusted height
        
        // Row 1
        [addrLabel.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor constant:2],
        [addrLabel.topAnchor constraintEqualToAnchor:controlPanel.topAnchor constant:5],
        [addrLabel.widthAnchor constraintEqualToConstant:40],
        
        [self.inputTextField.leadingAnchor constraintEqualToAnchor:addrLabel.trailingAnchor constant:2],
        [self.inputTextField.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [self.inputTextField.heightAnchor constraintEqualToConstant:22],
        [self.inputTextField.trailingAnchor constraintEqualToAnchor:jumpButton.leadingAnchor constant:-5],
        
        [jumpButton.trailingAnchor constraintEqualToAnchor:clearButton.leadingAnchor constant:-5],
        [jumpButton.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [jumpButton.widthAnchor constraintEqualToConstant:40],
        [jumpButton.heightAnchor constraintEqualToConstant:22],
        
        [clearButton.trailingAnchor constraintEqualToAnchor:self.exportAllButton.leadingAnchor constant:-5],
        [clearButton.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [clearButton.widthAnchor constraintEqualToConstant:40],
        [clearButton.heightAnchor constraintEqualToConstant:22],

        [self.exportAllButton.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-5],
        [self.exportAllButton.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [self.exportAllButton.widthAnchor constraintEqualToConstant:40],
        [self.exportAllButton.heightAnchor constraintEqualToConstant:22],

        // Close Button Constraints
        [closeButton.trailingAnchor constraintEqualToAnchor:controlPanel.trailingAnchor constant:-2],
        [closeButton.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [closeButton.widthAnchor constraintEqualToConstant:50], // Slightly wider
        [closeButton.heightAnchor constraintEqualToConstant:22],
        
        // Row 2 (Type Buttons)
        [self.dataTypeContainer.topAnchor constraintEqualToAnchor:self.inputTextField.bottomAnchor constant:5],
        [self.dataTypeContainer.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor],
        [self.dataTypeContainer.trailingAnchor constraintEqualToAnchor:controlPanel.trailingAnchor],
        [self.dataTypeContainer.heightAnchor constraintEqualToConstant:24],
        
        // Row 3 (Mode)
        [self.toggleModeButton.topAnchor constraintEqualToAnchor:self.dataTypeContainer.bottomAnchor constant:8],
        [self.toggleModeButton.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor],
        [self.toggleModeButton.widthAnchor constraintEqualToConstant:120],
        [self.toggleModeButton.heightAnchor constraintEqualToConstant:22],
        
        [self.selectionCountLabel.centerYAnchor constraintEqualToAnchor:self.toggleModeButton.centerYAnchor],
        [self.selectionCountLabel.leadingAnchor constraintEqualToAnchor:self.toggleModeButton.trailingAnchor constant:10],
        
        [saveButton.centerYAnchor constraintEqualToAnchor:self.toggleModeButton.centerYAnchor],
        [saveButton.trailingAnchor constraintEqualToAnchor:controlPanel.trailingAnchor constant:-2],
        [saveButton.widthAnchor constraintEqualToConstant:50],
        [saveButton.heightAnchor constraintEqualToConstant:22],
        
        [cancelSelButton.centerYAnchor constraintEqualToAnchor:self.toggleModeButton.centerYAnchor],
        [cancelSelButton.trailingAnchor constraintEqualToAnchor:saveButton.leadingAnchor constant:-5],
        [cancelSelButton.widthAnchor constraintEqualToConstant:60],
        [cancelSelButton.heightAnchor constraintEqualToConstant:22],
        
        [copyButton.centerYAnchor constraintEqualToAnchor:self.toggleModeButton.centerYAnchor],
        [copyButton.trailingAnchor constraintEqualToAnchor:cancelSelButton.leadingAnchor constant:-5],
        [copyButton.widthAnchor constraintEqualToConstant:60],
        [copyButton.heightAnchor constraintEqualToConstant:22],
        
        // TableView
        [self.tableView.topAnchor constraintEqualToAnchor:controlPanel.bottomAnchor constant:5],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:5],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-5],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-5]
    ]];
    
    // Layout Type Buttons
    for (int i = 0; i < self.typeButtons.count; i++) {
        UIButton *btn = self.typeButtons[i];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [btn.topAnchor constraintEqualToAnchor:self.dataTypeContainer.topAnchor],
            [btn.bottomAnchor constraintEqualToAnchor:self.dataTypeContainer.bottomAnchor]
        ]];
        
        if (i == 0) {
            [btn.leadingAnchor constraintEqualToAnchor:self.dataTypeContainer.leadingAnchor].active = YES;
        } else {
            [btn.leadingAnchor constraintEqualToAnchor:self.typeButtons[i-1].trailingAnchor constant:btnSpacing].active = YES;
        }
        
        if (i == self.typeButtons.count - 1) {
            [btn.trailingAnchor constraintEqualToAnchor:self.dataTypeContainer.trailingAnchor].active = YES;
        } else {
            [btn.widthAnchor constraintEqualToAnchor:self.typeButtons[i+1].widthAnchor].active = YES;
        }
    }
    
    // Default selection
    [self typeButtonTapped:self.typeButtons[0]];
    
    // Initialize logic
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *initialIndexPath = [NSIndexPath indexPathForRow:150 inSection:0];
        [self.tableView scrollToRowAtIndexPath:initialIndexPath 
                             atScrollPosition:UITableViewScrollPositionMiddle 
                                   animated:NO];
    });
    
    self.instructionBrowser = [[InstructionBrowser alloc] init];
    [self.instructionBrowser attachToSelf];
    self.highlightedRow = -1;
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:longPress];
    
    // Init arrays
    self.selectedIndexes = [NSMutableSet new];
    self.tableView.allowsMultipleSelection = YES;
    self.updateQueue = dispatch_queue_create("com.memoryUpdate.queue", DISPATCH_QUEUE_SERIAL);
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateMemoryValues) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.updateTimer forMode:NSRunLoopCommonModes];
    self.previousValues = [NSMutableDictionary new];
    self.cellColors = [NSMutableDictionary new];
    self.colorResetTimers = [NSMutableDictionary new];
    self.displayItems = [NSMutableArray array];
}

- (UIButton *)createCyberButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    btn.titleLabel.font = ImGuiFont(13, NO);
    btn.backgroundColor = IMGUI_BUTTON;
    btn.layer.cornerRadius = 2;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

- (void)typeButtonTapped:(UIButton *)sender {
    for (UIButton *button in self.typeButtons) {
        button.selected = (button == sender);
        button.backgroundColor = button.selected ? IMGUI_BUTTON_ACTIVE : IMGUI_BUTTON;
    }
    self.selectedTypeIndex = sender.tag;
    if (self.selectedTypeIndex == 4) {
        [self reloadAssemblyItems];
    } else {
        [self.displayItems removeAllObjects];
    }
    [self.previousValues removeAllObjects];
    [self.tableView reloadData];
}

- (void)reloadAssemblyItems {
    [self.displayItems removeAllObjects];
    
    for (int i = 0; i < 300; i++) {
        int64_t offset = (i - 150) * 4;
        uint64_t address = self.baseAddress + offset;
        
        uint32_t instruction = (uint32_t)[self.instructionBrowser readMemoryAtAddress:address size:4 error:nil];
        DisassembledInstruction *disasm = [ARM64Assembler disassemble:instruction atAddress:address];
        
        DisplayItem *item = [[DisplayItem alloc] init];
        item.instruction = disasm;
        item.depth = 0;
        item.isExpanded = NO;
        
        [self.displayItems addObject:item];
    }
}

- (void)modeButtonTapped:(UIButton *)sender {
    BOOL isSelectMode = ![self.editModeButtons[0] isHidden];
    BOOL newMode = !isSelectMode;
    
    // Update Button
    if (newMode) {
        [sender setTitle:@"多选模式: 开" forState:UIControlStateNormal];
        sender.backgroundColor = IMGUI_BUTTON_ACTIVE;
    } else {
        [sender setTitle:@"多选模式: 关" forState:UIControlStateNormal];
        sender.backgroundColor = IMGUI_BUTTON;
    }
    
    // Update Controls
    self.selectionCountLabel.hidden = !newMode;
    for (UIButton *btn in self.editModeButtons) {
        btn.hidden = !newMode;
    }
    
    self.isSelectionMode = newMode;
    
    if (!newMode) {
        [self.selectedIndexes removeAllObjects];
        self.selectionCountLabel.text = @"0";
        [self.tableView reloadData];
    }
}

- (void)closeButtonTapped {
    [[FloatingWindow sharedInstance] hide];
}

- (void)clearButtonTapped:(UIButton *)sender {
    self.inputTextField.text = @"";
}

- (void)jumpButtonTapped:(UIButton *)sender {
    NSString *inputText = self.inputTextField.text;
    if (inputText.length > 0) {
        unsigned long long jumpAddress;
        NSScanner *scanner = [NSScanner scannerWithString:inputText];
        if ([scanner scanHexLongLong:&jumpAddress]) {
            self.baseAddress = jumpAddress;
            self.highlightedRow = 150;
            
            if (self.selectedTypeIndex == 4) {
                [self reloadAssemblyItems];
            }
            
            NSIndexPath *middleIndexPath = [NSIndexPath indexPathForRow:150 inSection:0];
            [self.tableView scrollToRowAtIndexPath:middleIndexPath 
                                 atScrollPosition:UITableViewScrollPositionMiddle 
                                       animated:YES];
            [self.tableView reloadData];
        }
    }
    [self.previousValues removeAllObjects];
}

- (void)clearHighlight {
    self.highlightedRow = -1;
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.selectedTypeIndex == 4) {
        return self.displayItems.count;
    }
    return 300;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MemoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MemoryCell" forIndexPath:indexPath];
    
    // Background Color
    cell.backgroundColor = [UIColor clearColor];
    if (self.isSelectionMode && [self.selectedIndexes containsObject:@(indexPath.row)]) {
        cell.backgroundColor = IMGUI_BUTTON_ACTIVE;
    }
    
    if (self.selectedTypeIndex == 4) {
        DisplayItem *item = self.displayItems[indexPath.row];
        
        cell.addressLabel.text = [NSString stringWithFormat:@"0x%09llX", item.instruction.address];
        
        NSMutableString *valueStr = [NSMutableString string];
        for (int i = 0; i < item.depth; i++) {
            [valueStr appendString:@"    "];
        }
        
        if ([item.instruction.mnemonic isEqualToString:@".word"]) {
             [valueStr appendFormat:@".word 0x%08x", item.instruction.value];
        } else {
             [valueStr appendFormat:@"%@ %@", item.instruction.mnemonic, item.instruction.opStr];
        }
        
        cell.valueLabel.text = valueStr;
        
        // Expansion Button
        if (item.instruction.isBranchLink) {
            cell.expandButton.hidden = NO;
            [cell.expandButton setTitle:item.isExpanded ? @"▼" : @"▶" forState:UIControlStateNormal];
            
            __weak typeof(self) weakSelf = self;
            __weak typeof(cell) weakCell = cell;
            cell.expandBlock = ^{
                if (!weakSelf || !weakCell) return;
                NSIndexPath *currentIndexPath = [weakSelf.tableView indexPathForCell:weakCell];
                if (currentIndexPath) {
                    [weakSelf toggleExpansionAtIndexPath:currentIndexPath];
                }
            };
        } else {
            cell.expandButton.hidden = YES;
            cell.expandBlock = nil;
        }
        
        NSString *addressKey = [NSString stringWithFormat:@"%lld", item.instruction.address];
        UIColor *savedColor = self.cellColors[addressKey];
        cell.valueLabel.textColor = savedColor ? savedColor : IMGUI_TEXT;
        
    } else {
        cell.expandButton.hidden = YES;
        cell.expandBlock = nil;
        
        int64_t offset = (indexPath.row - 150) * 4;
        int64_t address = self.baseAddress + offset;
        NSString *addressKey = [NSString stringWithFormat:@"%lld", address];
        
        if (indexPath.row == self.highlightedRow) {
            cell.backgroundColor = [UIColor colorWithRed:0.3f green:0.5f blue:0.9f alpha:0.3f];
        }
        
        cell.addressLabel.text = [NSString stringWithFormat:@"0x%09llX", address];
        
        NSError *error = nil;
        NSString *valueStr = @"???";
        
        switch (self.selectedTypeIndex) {
            case 0: { // I32
                uint32_t value = (uint32_t)[self.instructionBrowser readMemoryAtAddress:address size:4 error:&error];
                if (!error) valueStr = [NSString stringWithFormat:@"%u", value];
                break;
            }
            case 1: { // I64
                uint64_t value = [self.instructionBrowser readMemoryAtAddress:address size:8 error:&error];
                if (!error) valueStr = [NSString stringWithFormat:@"%llu", value];
                break;
            }
            case 2: { // F32
                uint32_t intValue = (uint32_t)[self.instructionBrowser readMemoryAtAddress:address size:4 error:&error];
                if (!error) {
                    float floatValue;
                    memcpy(&floatValue, &intValue, sizeof(float));
                    valueStr = [NSString stringWithFormat:@"%f", floatValue];
                }
                break;
            }
            case 3: { // F64
                uint64_t intValue = [self.instructionBrowser readMemoryAtAddress:address size:8 error:&error];
                if (!error) {
                    double doubleValue;
                    memcpy(&doubleValue, &intValue, sizeof(double));
                    valueStr = [NSString stringWithFormat:@"%lf", doubleValue];
                }
                break;
            }
        }
        
        cell.valueLabel.text = valueStr;
        
        UIColor *savedColor = self.cellColors[addressKey];
        cell.valueLabel.textColor = savedColor ? savedColor : IMGUI_TEXT;
    }
    
    return cell;
}

- (void)toggleExpansionAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.displayItems.count) return;
    
    DisplayItem *item = self.displayItems[indexPath.row];
    if (!item.instruction.isBranchLink) return;
    
    if (item.isExpanded) {
        // Collapse
        item.isExpanded = NO;
        
        NSInteger count = 0;
        for (NSInteger i = indexPath.row + 1; i < self.displayItems.count; i++) {
            if (self.displayItems[i].depth > item.depth) {
                count++;
            } else {
                break;
            }
        }
        
        if (count > 0) {
            NSRange range = NSMakeRange(indexPath.row + 1, count);
            [self.displayItems removeObjectsInRange:range];
            
            NSMutableArray *indexPaths = [NSMutableArray array];
            for (int i = 0; i < count; i++) {
                [indexPaths addObject:[NSIndexPath indexPathForRow:indexPath.row + 1 + i inSection:0]];
            }
            [self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
        }
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        
    } else {
        // Expand
        item.isExpanded = YES;
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        
        uint64_t target = item.instruction.targetAddress;
        NSMutableArray<DisplayItem *> *newItems = [NSMutableArray array];
        
        for (int i = 0; i < 20; i++) {
            uint64_t addr = target + i * 4;
            uint32_t val = (uint32_t)[self.instructionBrowser readMemoryAtAddress:addr size:4 error:nil];
            DisassembledInstruction *disasm = [ARM64Assembler disassemble:val atAddress:addr];
            
            DisplayItem *newItem = [[DisplayItem alloc] init];
            newItem.instruction = disasm;
            newItem.depth = item.depth + 1;
            newItem.isExpanded = NO;
            [newItems addObject:newItem];
            
            if ([disasm.mnemonic isEqualToString:@"ret"]) break;
        }
        
        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(indexPath.row + 1, newItems.count)];
        [self.displayItems insertObjects:newItems atIndexes:indexes];
        
        NSMutableArray *indexPaths = [NSMutableArray array];
        for (int i = 0; i < newItems.count; i++) {
            [indexPaths addObject:[NSIndexPath indexPathForRow:indexPath.row + 1 + i inSection:0]];
        }
        [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    if (self.isSelectionMode) {
        NSNumber *row = @(indexPath.row);
        if ([self.selectedIndexes containsObject:row]) {
            [self.selectedIndexes removeObject:row];
        } else {
            [self.selectedIndexes addObject:row];
        }
        
        self.selectionCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.selectedIndexes.count];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    
    // ARM Edit Mode
    if (self.selectedTypeIndex == 4) {
        if (indexPath.row >= self.displayItems.count) return;
        DisplayItem *item = self.displayItems[indexPath.row];
        uint64_t address = item.instruction.address;
        
        NSError *error = nil;
        uint32_t currentInstruction = (uint32_t)[self.instructionBrowser readMemoryAtAddress:address size:4 error:&error];
        
        if (error) return;
        
        NSString *currentDisassembly = [ARM64Assembler disassembleInstruction:currentInstruction atAddress:address];
        
        SSInstructionEditView *editView = [[SSInstructionEditView alloc] initWithAddress:address currentInstruction:currentDisassembly];
        editView.delegate = self;
        [editView showInView:self.view];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 34;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
}

- (void)jumpToAddress:(uint64_t)address {
    NSString *addressString = [NSString stringWithFormat:@"0x%llX", address];
    self.inputTextField.text = addressString;
    
    self.baseAddress = address;
    self.highlightedRow = 150;
    
    [self.previousValues removeAllObjects];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        NSIndexPath *middleIndexPath = [NSIndexPath indexPathForRow:self.highlightedRow inSection:0];
        [self.tableView scrollToRowAtIndexPath:middleIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [self.tableView reloadRowsAtIndexPaths:@[middleIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)selectDataType:(NSInteger)typeIndex {
    if (typeIndex >= 0 && typeIndex < self.typeButtons.count) {
        [self typeButtonTapped:self.typeButtons[typeIndex]];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.updateTimer) {
        self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateMemoryValues) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.updateTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)dealloc {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    for (NSTimer *timer in self.colorResetTimers.allValues) {
        [timer invalidate];
    }
    [self.colorResetTimers removeAllObjects];
}

@end
