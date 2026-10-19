/*
 * ============================================================================
 *  指针链扫描（pointer chain scan）—— 本节代码标识
 *    ID      : 0CA2-4AD8-8E17-C3746067D85A
 *    日期时间: 2026-10-16 02:40:18
 *    引擎    : External/ptrscan/src（fast_ptrscan 源码，in-process）
 *    说明    : 区域枚举/索引/扫描/结果导出都在这里，UI 在 PointerScanPage，
 *              结果查看与两次对比在 FilterPage。
 * ============================================================================
 */

#import "UI/Pages/PointerScan/PointerScanPage.h"
#import "UI/Components/FloatingWindow.h"
#import "Modules/PointerScan/PointerScanner.h"
#import "Modules/PointerScan/PtrScanBridge.h"
#import "Services/LogService.h"
#import "UI/Pages/Scanner/FilterPage.h"
#import "UI/Components/ThemeConfig.h"

/*
 * 指针扫描页。参数直接对应 fast_ptrscan 的扫描选项：
 *
 *   目标地址        扫描的终点（要找到的那个值）
 *   每层窗口  -O    每层在目标下方多少字节内找候选
 *   层数      -d    最大指针深度
 *   每层上限  -k    每层每个父节点保留多少候选，0 = 不限（越大越慢越全）
 *   最短层数        过滤掉比它短的链
 *   最大结果数 -n   0 = 不限
 *   最大区域        丢弃大于该字节数的单个区域，0 = 不限
 *   线程数          建索引的线程数，0 = 自动
 *
 *   只扫可写内存    跳过只读区，索引小、建得快（文件映射里的地址用它扫不到）
 *   排除 dyld 缓存  跳过 dyld_shared_cache（几十万槽且几乎没有有用指针）
 *   低内存模式      索引大数组落盘，内存紧张时用（以时间换内存）
 */

/* v2：默认值换成实测在 pvz 上能出链的那套，旧设置不再沿用 */
static NSString *const kSettingsKey = @"PointerScanSettingsV5";

@interface PointerScanPage () <UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView  *mainStack;

@property (nonatomic, strong) UITextField *addressField;
@property (nonatomic, strong) UITextField *offsetField;
@property (nonatomic, strong) UITextField *levelField;
@property (nonatomic, strong) UITextField *offsetDeepField;
@property (nonatomic, strong) UITextField *maxTargetsField;
@property (nonatomic, strong) UITextField *minLevelField;
@property (nonatomic, strong) UITextField *maxChainsField;
@property (nonatomic, strong) UITextField *tailField;
@property (nonatomic, strong) UITextField *maxRegionField;
@property (nonatomic, strong) UITextField *jobsField;

@property (nonatomic, strong) UIButton *writableOnlyButton;
@property (nonatomic, strong) UIButton *excludeDyldButton;
@property (nonatomic, strong) UIButton *lowMemoryButton;

@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *rebuildButton;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UILabel  *resultLabel;
@property (nonatomic, strong) NSString *resultsFilePath;
@property (nonatomic, assign) BOOL scanning;

@end

@implementation PointerScanPage

#pragma mark - 控件工厂

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

- (UIButton *)createToggleWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = [self createCyberButtonWithTitle:title color:IMGUI_BUTTON action:action];
    btn.titleLabel.font = [UIFont systemFontOfSize:12];
    [btn.heightAnchor constraintEqualToConstant:30].active = YES;
    return btn;
}

- (void)setToggle:(UIButton *)btn on:(BOOL)on {
    btn.selected = on;
    btn.backgroundColor = on ? IMGUI_BUTTON_ACTIVE : IMGUI_BUTTON;
}

- (UITextField *)createCyberTextFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *tf = [[UITextField alloc] init];
    tf.placeholder = placeholder;
    tf.textColor = IMGUI_TEXT;
    tf.font = [UIFont systemFontOfSize:13];
    tf.backgroundColor = IMGUI_FRAME_BG;
    tf.layer.cornerRadius = 2;
    tf.keyboardType = UIKeyboardTypeASCIICapable;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.delegate = self;
    tf.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 20)];
    tf.leftView = paddingView;
    tf.leftViewMode = UITextFieldViewModeAlways;

    NSAttributedString *str = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{NSForegroundColorAttributeName: [UIColor lightGrayColor]}];
    tf.attributedPlaceholder = str;

    [tf.heightAnchor constraintEqualToConstant:30].active = YES;
    return tf;
}

- (UIView *)rowWithTitle:(NSString *)title field:(UITextField *)field {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.textColor = IMGUI_TEXT_DISABLED;
    label.font = [UIFont systemFontOfSize:12];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:96].active = YES;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ label, field ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 6;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMGUI_BG_COLOR;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"指针扫描 (fast_ptrscan)";
    titleLabel.textColor = IMGUI_TEXT;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];

    UIButton *closeButton = [self createCyberButtonWithTitle:@"返回" color:IMGUI_BUTTON
                                                     action:@selector(backButtonTapped)];
    [self.view addSubview:closeButton];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.mainStack = [[UIStackView alloc] init];
    self.mainStack.axis = UILayoutConstraintAxisVertical;
    self.mainStack.spacing = 8;
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStack];

    /* 参数输入 */
    self.addressField     = [self createCyberTextFieldWithPlaceholder:@"0x…"];
    self.offsetField      = [self createCyberTextFieldWithPlaceholder:@"1000"];
    self.offsetDeepField  = [self createCyberTextFieldWithPlaceholder:@"1000"];
    self.levelField       = [self createCyberTextFieldWithPlaceholder:@"5 (6 会撞内存预算)"];
    self.maxTargetsField  = [self createCyberTextFieldWithPlaceholder:@"8"];
    self.minLevelField    = [self createCyberTextFieldWithPlaceholder:@"0"];
    self.maxChainsField   = [self createCyberTextFieldWithPlaceholder:@"0 (不限)"];
    self.tailField        = [self createCyberTextFieldWithPlaceholder:@"0x58cc;0x20;0x0  每层一组"];
    self.maxRegionField   = [self createCyberTextFieldWithPlaceholder:@"40000000 (1GB)"];
    self.jobsField        = [self createCyberTextFieldWithPlaceholder:@"0 (自动)"];
    self.levelField.keyboardType      = UIKeyboardTypeNumberPad;
    self.maxTargetsField.keyboardType = UIKeyboardTypeNumberPad;
    self.minLevelField.keyboardType   = UIKeyboardTypeNumberPad;
    self.maxChainsField.keyboardType  = UIKeyboardTypeNumberPad;
    self.jobsField.keyboardType       = UIKeyboardTypeNumberPad;

    [self.mainStack addArrangedSubview:[self rowWithTitle:@"目标地址" field:self.addressField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"每层窗口 -O" field:self.offsetField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"其余层窗口" field:self.offsetDeepField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"层数 -d" field:self.levelField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"每层上限 -k" field:self.maxTargetsField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"最短层数" field:self.minLevelField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"最大结果数 -n" field:self.maxChainsField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"尾偏移 -t" field:self.tailField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"最大区域" field:self.maxRegionField]];
    [self.mainStack addArrangedSubview:[self rowWithTitle:@"索引线程" field:self.jobsField]];

    /* 开关 */
    self.writableOnlyButton = [self createToggleWithTitle:@"只扫可写内存"
                                                   action:@selector(toggleWritableOnly)];
    self.excludeDyldButton  = [self createToggleWithTitle:@"排除dyld缓存"
                                                   action:@selector(toggleExcludeDyld)];
    self.lowMemoryButton    = [self createToggleWithTitle:@"低内存模式"
                                                   action:@selector(toggleLowMemory)];

    UIStackView *toggles = [[UIStackView alloc] initWithArrangedSubviews:
                            @[ self.writableOnlyButton, self.excludeDyldButton, self.lowMemoryButton ]];
    toggles.axis = UILayoutConstraintAxisHorizontal;
    toggles.spacing = 6;
    toggles.distribution = UIStackViewDistributionFillEqually;
    [self.mainStack addArrangedSubview:toggles];

    /* 动作 */
    self.scanButton   = [self createCyberButtonWithTitle:@"开始扫描" color:IMGUI_BUTTON
                                                 action:@selector(scanButtonTapped)];
    self.stopButton   = [self createCyberButtonWithTitle:@"停止扫描" color:IMGUI_BUTTON
                                                 action:@selector(stopButtonTapped)];
    self.rebuildButton = [self createCyberButtonWithTitle:@"重建索引（改了过滤条件后用）"
                                                    color:IMGUI_BUTTON
                                                   action:@selector(rebuildButtonTapped)];
    self.filterButton = [self createCyberButtonWithTitle:@"筛选/查看结果" color:IMGUI_BUTTON
                                                 action:@selector(filterButtonTapped)];
    [self.rebuildButton.heightAnchor constraintEqualToConstant:30].active = YES;
    [self.mainStack addArrangedSubview:self.rebuildButton];
    [self.scanButton.heightAnchor constraintEqualToConstant:32].active = YES;
    [self.stopButton.heightAnchor constraintEqualToConstant:30].active = YES;
    [self.filterButton.heightAnchor constraintEqualToConstant:30].active = YES;
    [self.mainStack addArrangedSubview:self.scanButton];
    [self.mainStack addArrangedSubview:self.stopButton];
    [self.mainStack addArrangedSubview:self.filterButton];

    /* 状态 */
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;

    self.resultLabel = [[UILabel alloc] init];
    self.resultLabel.text = @"";
    self.resultLabel.textColor = IMGUI_TEXT_DISABLED;
    self.resultLabel.font = [UIFont systemFontOfSize:11];
    self.resultLabel.numberOfLines = 0;
    self.resultLabel.textAlignment = NSTextAlignmentCenter;

    [self.mainStack addArrangedSubview:self.statusLabel];
    [self.mainStack addArrangedSubview:self.resultLabel];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:10],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [closeButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [closeButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-10],
        [closeButton.widthAnchor constraintEqualToConstant:60],
        [closeButton.heightAnchor constraintEqualToConstant:28],

        [self.scrollView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:10],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-10],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],

        [self.mainStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.mainStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.mainStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.mainStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20],
        [self.mainStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];

    [self loadSettings];

    /* 恢复上次的结果文件（页面被重建后用“筛选/查看结果”仍然有东西可看） */
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"PointerScanLastResults"];

    if (saved.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:saved])
        self.resultsFilePath = saved;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

#pragma mark - 参数持久化

- (void)loadSettings {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingsKey] ?: @{};

    self.offsetField.text     = d[@"maxOffset"]  ?: @"10000";
    self.offsetDeepField.text = d[@"maxOffsetDeep"] ?: @"10000";
    self.levelField.text      = d[@"maxDepth"]   ?: @"5";
    self.maxTargetsField.text = d[@"maxK"]       ?: @"8";
    self.minLevelField.text   = d[@"minDepth"]   ?: @"0";
    self.maxChainsField.text  = d[@"maxChains"]  ?: @"0";
    self.tailField.text       = d[@"tail"]       ?: @"";
    self.maxRegionField.text  = d[@"maxRegion"]  ?: @"40000000";
    self.jobsField.text       = d[@"jobs"]       ?: @"0";
    self.addressField.text    = d[@"address"]    ?: @"";

    [self setToggle:self.writableOnlyButton
                 on:d[@"writableOnly"] ? [d[@"writableOnly"] boolValue] : NO];
    /* 默认不排除：上游指针槽很可能就在共享缓存里，排除掉会“命中 0” */
    [self setToggle:self.excludeDyldButton  on:d[@"excludeDyld"] ? [d[@"excludeDyld"] boolValue] : NO];
    [self setToggle:self.lowMemoryButton    on:d[@"lowMemory"]   ? [d[@"lowMemory"] boolValue]   : YES];
}

- (void)saveSettings {
    NSDictionary *d = @{
        @"address":      self.addressField.text ?: @"",
        @"maxOffset":    self.offsetField.text ?: @"10000",
        @"maxOffsetDeep": self.offsetDeepField.text ?: @"10000",
        @"maxDepth":     self.levelField.text ?: @"5",
        @"maxK":         self.maxTargetsField.text ?: @"8",
        @"minDepth":     self.minLevelField.text ?: @"0",
        @"maxChains":    self.maxChainsField.text ?: @"0",
        @"tail":         self.tailField.text ?: @"",
        @"maxRegion":    self.maxRegionField.text ?: @"40000000",
        @"jobs":         self.jobsField.text ?: @"0",
        @"writableOnly": @(self.writableOnlyButton.selected),
        @"excludeDyld":  @(self.excludeDyldButton.selected),
        @"lowMemory":    @(self.lowMemoryButton.selected),
    };
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kSettingsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - 工具

- (uint64_t)hexFromField:(UITextField *)field fallback:(uint64_t)fallback {
    NSString *s = [field.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    if ([s hasPrefix:@"0x"] || [s hasPrefix:@"0X"]) s = [s substringFromIndex:2];
    if (s.length == 0) return fallback;
    return strtoull([s UTF8String], NULL, 16);
}

- (NSInteger)intFromField:(UITextField *)field fallback:(NSInteger)fallback {
    NSString *s = [field.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    if (s.length == 0) return fallback;
    return [s integerValue];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)toggleWritableOnly {
    [self setToggle:self.writableOnlyButton on:!self.writableOnlyButton.selected];
    [self saveSettings];
}

- (void)toggleExcludeDyld {
    [self setToggle:self.excludeDyldButton on:!self.excludeDyldButton.selected];
    [self saveSettings];
}

- (void)toggleLowMemory {
    [self setToggle:self.lowMemoryButton on:!self.lowMemoryButton.selected];
    [self saveSettings];
}

- (void)setScanningUI:(BOOL)scanning {
    self.scanning = scanning;
    self.scanButton.enabled = !scanning;
    [self.scanButton setTitleColor:(scanning ? [UIColor grayColor] : IMGUI_TEXT)
                          forState:UIControlStateNormal];
    self.stopButton.enabled = scanning;
    [self.stopButton setTitleColor:(scanning ? IMGUI_TEXT : [UIColor grayColor])
                          forState:UIControlStateNormal];
}

#pragma mark - 动作

/*
 * 无论有没有扫描结果，这个按钮都能用：
 *   1) 有当前结果 → 自动加载；
 *   2) 路径丢了（页面重建）或文件被清理 → 用 tmp 里最新的结果文件；
 *   3) 一个都没有 → 打开空页面，可以手动“加载”历史文件或用“对比”比较两次结果。
 */
- (void)filterButtonTapped {
    NSString *path = self.resultsFilePath;

    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString *latest = [[PointerScanner sharedScanner] latestResultsPath];

        if (latest.length > 0) {
            path = latest;
            self.resultsFilePath = latest;
        }
    }

    [LoggingService log:@"点击了筛选按钮（结果文件: %@）",
     path.length ? path.lastPathComponent : @"无（可手动加载）"];

    FilterPage *filterVC = [[FilterPage alloc] init];
    filterVC.initialFilePath = path;
    if (filterVC) {
        [self addChildViewController:filterVC];
        [self.view addSubview:filterVC.view];

        filterVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [filterVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [filterVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [filterVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [filterVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];

        [filterVC didMoveToParentViewController:self];
    }
}

- (void)backButtonTapped {
    [[PointerScanner sharedScanner] stopScan];
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)scanButtonTapped {
    [self dismissKeyboard];
    [self saveSettings];

    uint64_t target = [self hexFromField:self.addressField fallback:0];
    if (target == 0) {
        self.statusLabel.text = @"请输入有效的目标地址（十六进制）";
        return;
    }

    PtrScanOptions *o = [[PtrScanOptions alloc] init];
    o.targetAddress     = target;
    o.targetPID         = 0;                                   /* 本进程 */
    o.maxDepth          = (int)[self intFromField:self.levelField fallback:5];
    o.maxOffset         = [self hexFromField:self.offsetField fallback:0x10000];
    o.maxOffsetDeep     = [self hexFromField:self.offsetDeepField fallback:o.maxOffset];
    o.maxTargetsPerNode = (int)[self intFromField:self.maxTargetsField fallback:8];
    o.minDepth          = (int)[self intFromField:self.minLevelField fallback:0];
    o.maxChains         = [self intFromField:self.maxChainsField fallback:0];
    o.tailOffsets       = self.tailField.text.length ? self.tailField.text : nil;
    o.maxRegion         = [self hexFromField:self.maxRegionField fallback:0];
    o.jobs              = (int)[self intFromField:self.jobsField fallback:0];

    o.writableOnly      = self.writableOnlyButton.selected;
    o.excludeNames      = self.excludeDyldButton.selected ? @[ @"dyld_shared_cache" ] : @[];
    o.lowMemory         = self.lowMemoryButton.selected;

    if (o.maxOffset == 0) o.maxOffset = 0x1000;
    if (o.maxOffsetDeep == 0) o.maxOffsetDeep = o.maxOffset;
    if (o.maxDepth <= 0)  o.maxDepth = 5;
    if (o.maxDepth > 32)  o.maxDepth = 32;
    if (o.maxOffset > 0x7FFFFFFFULL) o.maxOffset = 0x7FFFFFFFULL;

    /* 注意：不要在这里清掉上一次的结果路径 —— 扫描失败/中止时它还能用 */
    self.resultLabel.text = @"";
    [self setScanningUI:YES];
    self.statusLabel.text = @"启动扫描…";

    [LoggingService log:@"[指针扫描] 参数 目标=0x%llX 窗口=0x%llX 层数=%d k=%d 最短=%d 最多=%ld 尾=[%@] 区域上限=0x%llX 可写=%d 排除dyld=%d 低内存=%d",
     (unsigned long long)o.targetAddress, (unsigned long long)o.maxOffset,
     o.maxDepth, o.maxTargetsPerNode, o.minDepth, (long)o.maxChains,
     o.tailOffsets ?: @"", (unsigned long long)o.maxRegion, o.writableOnly,
     self.excludeDyldButton.selected, o.lowMemory];

    __weak typeof(self) weakSelf = self;
    [[PointerScanner sharedScanner] startScanWithOptions:o
        completion:^(NSString *resultsFilePath, NSUInteger count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;

                [strongSelf setScanningUI:NO];

                if (!resultsFilePath) {
                    strongSelf.statusLabel.text = @"扫描未完成：日志里有原因（多为层数/窗口过大的内存预算中止）";
                    return;
                }

                strongSelf.resultsFilePath = resultsFilePath;
                [[NSUserDefaults standardUserDefaults] setObject:resultsFilePath
                                                          forKey:@"PointerScanLastResults"];
                strongSelf.statusLabel.text = [NSString stringWithFormat:@"扫描完成：%lu 条链", (unsigned long)count];
                strongSelf.resultLabel.text = [NSString stringWithFormat:
                    @"%@（%lu 条）→ 点“筛选/查看结果”查看",
                    resultsFilePath.lastPathComponent, (unsigned long)count];
            });
        }
        progressBlock:^(float progress, NSString *status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf.statusLabel.text = [NSString stringWithFormat:@"%@ (%.0f%%)",
                                               status, progress * 100.0f];
            });
        }
        foundResultBlock:^(NSUInteger count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf.resultLabel.text = [NSString stringWithFormat:@"已找到 %lu 条链", (unsigned long)count];
            });
        }];
}

- (void)rebuildButtonTapped {
    [[PtrScanBridge sharedBridge] invalidateIndexCache];
    self.statusLabel.text = @"索引缓存已清空：下次扫描会重建（约 20 秒）";
}

- (void)stopButtonTapped {
    [[PointerScanner sharedScanner] stopScan];
    self.statusLabel.text = @"已请求停止…";
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self saveSettings];
    return YES;
}

@end
