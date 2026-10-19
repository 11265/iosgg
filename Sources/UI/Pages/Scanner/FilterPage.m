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

#import "UI/Pages/Scanner/FilterPage.h"
#import "UI/Components/FloatingWindow.h"
#import "Services/LogService.h"
#import "Core/Memory/SSMemoryBridge.h"
#import "Modules/PointerScan/PointerScanner.h"
#import <mach-o/dyld.h>

#import "UI/Components/ThemeConfig.h"
#import "UI/Dialogs/FileSelectionOverlay.h"
#import "UI/Dialogs/FilterSettingsOverlay.h"
@interface PointerChainItem : NSObject
@property (nonatomic, strong) PointerChainNode *root;
@property (nonatomic, copy) NSArray<NSNumber *> *offsets;
@property (nonatomic, copy) NSString *moduleName;
@property (nonatomic, assign) uint64_t baseOffset;
@property (nonatomic, assign) NSInteger level;
@property (nonatomic, assign) BOOL hasValidation;
@property (nonatomic, assign) BOOL isValid;
@property (nonatomic, assign) uint64_t finalAddress;
@property (nonatomic, assign) uint64_t finalValue;
@end

@implementation PointerChainItem
@end

@interface FilterPage () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<PointerChainItem *> *allItems;
@property (nonatomic, strong) NSMutableArray<PointerChainItem *> *filteredItems;
@property (nonatomic, strong) NSMutableArray<PointerChainItem *> *displayItems;
@property (nonatomic, strong) NSMutableSet<PointerChainItem *> *expandedItems;
@property (nonatomic, strong) PointerFilterSettings *filterSettings;
@property (nonatomic, strong) UIButton *compareButton;
@property (nonatomic, copy)   NSString *actionInfo;
@property (nonatomic, copy)   NSString *compareFirstPath;
@property (nonatomic, copy)   NSString *compareSecondPath;
@property (nonatomic, copy)   NSString *compareHint;
@property (nonatomic, copy)   NSString *compareInfo;
@property (nonatomic, copy)   NSString *comparePath;
@property (nonatomic, strong) UIButton *loadButton;
@property (nonatomic, strong) UIButton *readButton;
@property (nonatomic, strong) UIButton *verifyButton;
@property (nonatomic, strong) UIButton *deleteButton; // 新增删除按钮
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *filterSummaryLabel;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UISegmentedControl *pageSizeControl;
@property (nonatomic, strong) UIButton *prevPageButton;
@property (nonatomic, strong) UIButton *nextPageButton;
@property (nonatomic, strong) UIView *paginationBar;
@property (nonatomic, assign) NSInteger currentPage;
@property (nonatomic, assign) NSInteger pageSize;
@end

@implementation FilterPage

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
    self.allItems = [NSMutableArray array];
    self.filteredItems = [NSMutableArray array];
    self.displayItems = [NSMutableArray array];
    self.expandedItems = [NSMutableSet set];
    self.pageSize = 100;
    self.currentPage = 0;
    self.filterSettings = [self loadSavedFilterSettings] ?: [[PointerFilterSettings alloc] init];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"筛选";
    titleLabel.textColor = IMGUI_TEXT;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];
    
    UIStackView *buttonStack = [[UIStackView alloc] init];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.distribution = UIStackViewDistributionFillEqually;
    buttonStack.spacing = 8;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:buttonStack];
    
    self.loadButton = [self createCyberButtonWithTitle:@"加载" color:IMGUI_BUTTON action:@selector(loadButtonTapped)];
    self.readButton = [self createCyberButtonWithTitle:@"读取" color:IMGUI_BUTTON action:@selector(readButtonTapped)];
    self.verifyButton = [self createCyberButtonWithTitle:@"校验" color:IMGUI_BUTTON action:@selector(verifyButtonTapped)];
    self.deleteButton = [self createCyberButtonWithTitle:@"管理" color:IMGUI_BUTTON action:@selector(deleteButtonTapped)];
    self.compareButton = [self createCyberButtonWithTitle:@"对比" color:IMGUI_BUTTON action:@selector(compareButtonTapped)];
    self.backButton = [self createCyberButtonWithTitle:@"返回" color:IMGUI_BUTTON action:@selector(backButtonTapped)];
    
    [buttonStack addArrangedSubview:self.loadButton];
    [buttonStack addArrangedSubview:self.compareButton];
    [buttonStack addArrangedSubview:self.readButton];
    [buttonStack addArrangedSubview:self.verifyButton];
    [buttonStack addArrangedSubview:self.deleteButton];
    [buttonStack addArrangedSubview:self.backButton];
    
    UIView *filterBar = [[UIView alloc] init];
    filterBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:filterBar];
    
    self.filterSummaryLabel = [[UILabel alloc] init];
    self.filterSummaryLabel.textColor = IMGUI_TEXT;
    self.filterSummaryLabel.font = [UIFont systemFontOfSize:12];
    self.filterSummaryLabel.numberOfLines = 2;
    self.filterSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [filterBar addSubview:self.filterSummaryLabel];
    
    UIButton *filterButton = [self createCyberButtonWithTitle:@"筛选" color:IMGUI_BUTTON action:@selector(filterSettingsTapped)];
    UIButton *saveFilterButton = [self createCyberButtonWithTitle:@"保存结果" color:IMGUI_BUTTON action:@selector(saveFilterTapped)];
    [filterBar addSubview:filterButton];
    [filterBar addSubview:saveFilterButton];
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [UIColor darkGrayColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    
    self.paginationBar = [[UIView alloc] init];
    self.paginationBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.paginationBar];
    
    self.prevPageButton = [self createCyberButtonWithTitle:@"上一页" color:IMGUI_BUTTON action:@selector(prevPageTapped)];
    self.nextPageButton = [self createCyberButtonWithTitle:@"下一页" color:IMGUI_BUTTON action:@selector(nextPageTapped)];
    self.pageLabel = [[UILabel alloc] init];
    self.pageLabel.textColor = IMGUI_TEXT;
    self.pageLabel.font = [UIFont systemFontOfSize:12];
    self.pageLabel.textAlignment = NSTextAlignmentCenter;
    self.pageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.pageSizeControl = [[UISegmentedControl alloc] initWithItems:@[@"50", @"100", @"200"]];
    self.pageSizeControl.selectedSegmentIndex = 1;
    self.pageSizeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pageSizeControl addTarget:self action:@selector(pageSizeChanged:) forControlEvents:UIControlEventValueChanged];
    
    [self.paginationBar addSubview:self.prevPageButton];
    [self.paginationBar addSubview:self.nextPageButton];
    [self.paginationBar addSubview:self.pageLabel];
    [self.paginationBar addSubview:self.pageSizeControl];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:10],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [buttonStack.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
        [buttonStack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:10],
        [buttonStack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-10],
        [buttonStack.heightAnchor constraintEqualToConstant:30],
        
        [filterBar.topAnchor constraintEqualToAnchor:buttonStack.bottomAnchor constant:8],
        [filterBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:10],
        [filterBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-10],
        [filterBar.heightAnchor constraintEqualToConstant:44],
        
        [filterButton.centerYAnchor constraintEqualToAnchor:filterBar.centerYAnchor],
        [filterButton.trailingAnchor constraintEqualToAnchor:filterBar.trailingAnchor],
        [filterButton.widthAnchor constraintEqualToConstant:50],
        [filterButton.heightAnchor constraintEqualToConstant:26],
        
        [saveFilterButton.centerYAnchor constraintEqualToAnchor:filterBar.centerYAnchor],
        [saveFilterButton.trailingAnchor constraintEqualToAnchor:filterButton.leadingAnchor constant:-6],
        [saveFilterButton.widthAnchor constraintEqualToConstant:50],
        [saveFilterButton.heightAnchor constraintEqualToConstant:26],
        
        [self.filterSummaryLabel.leadingAnchor constraintEqualToAnchor:filterBar.leadingAnchor],
        [self.filterSummaryLabel.trailingAnchor constraintEqualToAnchor:saveFilterButton.leadingAnchor constant:-8],
        [self.filterSummaryLabel.centerYAnchor constraintEqualToAnchor:filterBar.centerYAnchor],
        
        [self.tableView.topAnchor constraintEqualToAnchor:filterBar.bottomAnchor constant:6],
        [self.tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        
        [self.paginationBar.topAnchor constraintEqualToAnchor:self.tableView.bottomAnchor constant:6],
        [self.paginationBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:10],
        [self.paginationBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-10],
        [self.paginationBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-6],
        [self.paginationBar.heightAnchor constraintEqualToConstant:34],
        
        [self.prevPageButton.leadingAnchor constraintEqualToAnchor:self.paginationBar.leadingAnchor],
        [self.prevPageButton.centerYAnchor constraintEqualToAnchor:self.paginationBar.centerYAnchor],
        [self.prevPageButton.widthAnchor constraintEqualToConstant:60],
        [self.prevPageButton.heightAnchor constraintEqualToConstant:26],
        
        [self.nextPageButton.trailingAnchor constraintEqualToAnchor:self.paginationBar.trailingAnchor],
        [self.nextPageButton.centerYAnchor constraintEqualToAnchor:self.paginationBar.centerYAnchor],
        [self.nextPageButton.widthAnchor constraintEqualToConstant:60],
        [self.nextPageButton.heightAnchor constraintEqualToConstant:26],
        
        [self.pageLabel.centerYAnchor constraintEqualToAnchor:self.paginationBar.centerYAnchor],
        [self.pageLabel.centerXAnchor constraintEqualToAnchor:self.paginationBar.centerXAnchor],
        
        [self.pageSizeControl.centerYAnchor constraintEqualToAnchor:self.paginationBar.centerYAnchor],
        [self.pageSizeControl.trailingAnchor constraintEqualToAnchor:self.nextPageButton.leadingAnchor constant:-8],
        [self.pageSizeControl.widthAnchor constraintEqualToConstant:150],
        [self.pageSizeControl.heightAnchor constraintEqualToConstant:26]
    ]];
    
    [self updateFilterSummary];
    [self updatePagination];

    if (self.initialFilePath.length == 0) {
        /* 兜底：直接打开时也自动找最近一次的结果，找不到就留空页面让用户手动加载 */
        NSString *latest = [[PointerScanner sharedScanner] latestResultsPath];

        if (latest.length > 0) {
            self.initialFilePath = latest;
            [LoggingService log:@"[筛选] 没有指定文件，自动使用最近一次结果: %@",
             latest.lastPathComponent];
        }
    }

    /* 指针扫描页带过来的结果文件：进页面就自动加载、校验、算值 */
    if (self.initialFilePath.length > 0) {
        [LoggingService log:@"[筛选] 自动加载指针扫描结果: %@", self.initialFilePath];
        [self loadResultsFromFile:self.initialFilePath];
    }
}

#pragma mark - Actions

- (void)loadButtonTapped {
    [LoggingService log:@"点击了加载按钮，显示文件选择..."];
    
    FileSelectionOverlay *overlay = [[FileSelectionOverlay alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    __weak typeof(self) weakSelf = self;
    overlay.onFileSelected = ^(NSString *path) {
        [weakSelf loadResultsFromFile:path];
    };
    
    [self.view addSubview:overlay];
}

/*
 * 两次结果对比：加载第二份结果文件，只保留两份里都存在的链。
 *
 * 用途：同一个地址在不同时间/不同关卡各扫一次，只留下"两次都成立"的链，
 * 这样筛出来的就是稳定的静态链，而不是那一局偶然命中的。
 */
- (NSString *)chainKeyForItem:(PointerChainItem *)item {
    NSMutableString *key = [NSMutableString stringWithFormat:@"%@|0x%llX",
                            item.moduleName ?: @"", (unsigned long long)item.baseOffset];

    for (NSNumber *o in item.offsets) {
        [key appendFormat:@"|%lld", (long long)o.longLongValue];
    }
    return key;
}

- (void)pickFileWithTitle:(NSString *)title handler:(void (^)(NSString *path))handler {
    self.compareHint = title;
    [self updateFilterSummary];
    [LoggingService log:@"[筛选] %@", title];

    __weak typeof(self) weakSelf = self;
    FileSelectionOverlay *overlay = [[FileSelectionOverlay alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.onFileSelected = ^(NSString *path) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.compareHint = nil;
        [strongSelf updateFilterSummary];
        handler(path);
    };
    [self.view addSubview:overlay];
}

/*
 * 对比：连续选两份结果文件，然后只显示两份里都存在的链。
 *   第 1 步 选第一份 → 第 2 步 选第二份 → 立刻求交集并显示。
 */
- (void)compareButtonTapped {
    [LoggingService log:@"点击对比按钮：需要依次选择两份结果文件"];

    __weak typeof(self) weakSelf = self;

    [self pickFileWithTitle:@"对比 1/2：请选择第一份结果" handler:^(NSString *first) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf.compareFirstPath = first;
        [LoggingService log:@"[筛选] 对比第一份: %@", first.lastPathComponent];

        /* 等选择器收起后再弹第二个，避免两个浮层打架 */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) inner = weakSelf;
            if (!inner) return;

            [inner pickFileWithTitle:@"对比 2/2：请选择第二份结果" handler:^(NSString *second) {
                __strong typeof(weakSelf) done = weakSelf;
                if (!done) return;

                done.compareSecondPath = second;
                [LoggingService log:@"[筛选] 对比第二份: %@", second.lastPathComponent];
                [done compareFirst:done.compareFirstPath second:second];
            }];
        });
    }];
}

- (void)compareFirst:(NSString *)firstPath second:(NSString *)secondPath {
    NSArray<PointerChainItem *> *first  = [self itemsFromFile:firstPath];
    NSArray<PointerChainItem *> *second = [self itemsFromFile:secondPath];

    if (first.count == 0 || second.count == 0) {
        [self showAlert:@"对比失败"
                message:[NSString stringWithFormat:@"读取到的链数：第一份 %lu，第二份 %lu。请确认选的是结果文件（pointer_scan_*.txt）。",
                         (unsigned long)first.count, (unsigned long)second.count]];
        return;
    }

    NSMutableSet<NSString *> *secondKeys = [NSMutableSet setWithCapacity:second.count];
    for (PointerChainItem *item in second) {
        [secondKeys addObject:[self chainKeyForItem:item]];
    }

    NSMutableArray<PointerChainItem *> *common = [NSMutableArray array];
    for (PointerChainItem *item in first) {
        if ([secondKeys containsObject:[self chainKeyForItem:item]])
            [common addObject:item];
    }

    self.allItems     = common;
    self.comparePath  = secondPath;
    self.compareInfo  = [NSString stringWithFormat:@"对比 %@(%lu) ∩ %@(%lu) → 共同 %lu",
                         firstPath.lastPathComponent, (unsigned long)first.count,
                         secondPath.lastPathComponent, (unsigned long)second.count,
                         (unsigned long)common.count];

    [LoggingService log:@"[筛选] %@", self.compareInfo];

    [self validateItems:self.allItems updateValue:YES];
    [self applyFilterSettingsAndRefresh];

    [self showAlert:@"对比完成"
            message:[NSString stringWithFormat:@"第一份 %@：%lu 条\n第二份 %@：%lu 条\n\n两份都有：%lu 条（现在只显示这些）",
                     firstPath.lastPathComponent, (unsigned long)first.count,
                     secondPath.lastPathComponent, (unsigned long)second.count,
                     (unsigned long)common.count]];
}

- (void)compareWithFile:(NSString *)path {
    NSArray<PointerChainItem *> *first = [self.allItems copy];
    NSUInteger firstCount = first.count;

    /* 借 loadResultsFromFile: 解析第二份（它会填充 allItems 并校验） */
    [self loadResultsFromFile:path];
    NSArray<PointerChainItem *> *second = [self.allItems copy];
    NSUInteger secondCount = second.count;

    NSMutableSet<NSString *> *secondKeys = [NSMutableSet setWithCapacity:secondCount];
    for (PointerChainItem *item in second) {
        [secondKeys addObject:[self chainKeyForItem:item]];
    }

    NSMutableArray<PointerChainItem *> *common = [NSMutableArray array];
    for (PointerChainItem *item in first) {
        if ([secondKeys containsObject:[self chainKeyForItem:item]])
            [common addObject:item];
    }

    self.allItems  = common;
    self.comparePath = path;
    self.compareInfo = [NSString stringWithFormat:@"对比 %lu ∪ %lu → 共同 %lu",
                        (unsigned long)firstCount, (unsigned long)secondCount,
                        (unsigned long)common.count];

    [LoggingService log:@"[筛选] %@（B: %@）", self.compareInfo, path.lastPathComponent];

    [self validateItems:self.allItems updateValue:YES];
    [self applyFilterSettingsAndRefresh];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"对比完成"
        message:[NSString stringWithFormat:@"第一份 %lu 条\n第二份 %lu 条\n两份都有 %lu 条（已只保留这些）",
                 (unsigned long)firstCount, (unsigned long)secondCount,
                 (unsigned long)common.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteButtonTapped {
    [LoggingService log:@"点击了管理按钮，显示文件列表进行管理..."];
    
    FileSelectionOverlay *overlay = [[FileSelectionOverlay alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // __weak typeof(self) weakSelf = self; // Unused variable
    overlay.onFileDeleted = ^(NSString *path) {
        [LoggingService log:@"已删除文件: %@", path.lastPathComponent];
    };
    
    [self.view addSubview:overlay];
}

- (void)filterSettingsTapped {
    FilterSettingsOverlay *overlay = [[FilterSettingsOverlay alloc] initWithFrame:self.view.bounds current:self.filterSettings];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak typeof(self) weakSelf = self;
    overlay.onApply = ^(PointerFilterSettings *settings) {
        weakSelf.filterSettings = settings;
        [weakSelf saveFilterSettings:settings];
        [weakSelf applyFilterSettingsAndRefresh];
    };
    [self.view addSubview:overlay];
}

/*
 * 保存：把**当前筛选（或两次对比）之后的链**导出成一个新的结果文件。
 *   - 两次对比后点保存 → 存的就是“共同的那批链”；
 *   - 单次加载/扫描后筛选再保存 → 存的就是筛选后的那批。
 * 导出格式与扫描输出完全一致（[模块 + 基址] -> +增量 …），所以新文件能再次
 * 被“加载”，也能拿去和别的结果“对比”。筛选条件本身在筛选面板点“应用”时
 * 已经自动保存，这里顺带再存一次。
 */
- (void)saveFilterTapped {
    NSArray<PointerChainItem *> *items = self.filteredItems.count > 0
        ? self.filteredItems
        : self.allItems;

    NSString *scope = self.filteredItems.count > 0 ? @"筛选后" : @"全部";

    if (items.count == 0) {
        [self showAlert:@"没有可保存的链" message:@"先扫描或加载一份结果，再点保存。"];
        return;
    }

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale     = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";

    NSString *stamp  = [fmt stringFromDate:[NSDate date]];
    NSString *uuid   = [[NSUUID UUID] UUIDString];
    NSString *short8 = uuid.length >= 8 ? [uuid substringToIndex:8] : uuid;
    NSString *name   = [NSString stringWithFormat:@"pointer_scan_%@-%@-saved.txt", short8, stamp];
    NSString *path   = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

    NSMutableString *out = [NSMutableString string];
    NSString *nowStr = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                      dateStyle:NSDateFormatterShortStyle
                                                      timeStyle:NSDateFormatterMediumStyle];
    [out appendFormat:@"# 指针链扫描 0CA2-4AD8-8E17-C3746067D85A  %@  保存（%@）  %lu 条%@\n",
     nowStr, scope, (unsigned long)items.count,
     self.compareInfo.length ? [@"，" stringByAppendingString:self.compareInfo] : @""];

    for (PointerChainItem *item in items) {
        [out appendFormat:@"[%@ + 0x%llX]", item.moduleName,
         (unsigned long long)item.baseOffset];

        for (NSNumber *num in item.offsets) {
            long long d = num.longLongValue;

            if (d < 0)
                [out appendFormat:@" -> -0x%llX", (unsigned long long)(-d)];
            else
                [out appendFormat:@" -> +0x%llX", (unsigned long long)d];
        }
        [out appendString:@"\n"];
    }

    NSError *err = nil;
    if (![out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        [self showAlert:@"保存失败" message:err.localizedDescription ?: @"写入失败"];
        return;
    }

    [self saveFilterSettings:self.filterSettings];
    [self updateFilterSummary];

    self.actionInfo = [NSString stringWithFormat:@"已保存 %lu 条：%@",
                       (unsigned long)items.count, name];
    [LoggingService log:@"[筛选] %@", self.actionInfo];

    [self showAlert:@"已保存"
            message:[NSString stringWithFormat:@"%@\n\n%@\n\n可在“加载”里重新打开，也可与其它结果“对比”。",
                     name, self.actionInfo]];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)verifyButtonTapped {
    [self validateItems:self.allItems updateValue:NO];

    NSUInteger valid = 0, invalid = 0;

    for (PointerChainItem *item in self.allItems) {
        if (item.isValid) valid++;
        else              invalid++;
    }

    self.actionInfo = [NSString stringWithFormat:@"校验：有效 %lu / 无效 %lu（未刷新值）",
                       (unsigned long)valid, (unsigned long)invalid];
    [LoggingService log:@"[筛选] %@", self.actionInfo];

    [self applyFilterSettingsAndRefresh];
}

- (void)prevPageTapped {
    if (self.currentPage > 0) {
        self.currentPage -= 1;
        [self updatePagination];
    }
}

- (void)nextPageTapped {
    NSInteger totalPages = [self totalPages];
    if (self.currentPage + 1 < totalPages) {
        self.currentPage += 1;
        [self updatePagination];
    }
}

- (void)pageSizeChanged:(UISegmentedControl *)sender {
    NSArray<NSNumber *> *sizes = @[@50, @100, @200];
    NSInteger index = sender.selectedSegmentIndex;
    if (index >= 0 && index < sizes.count) {
        self.pageSize = sizes[index].integerValue;
        self.currentPage = 0;
        [self updatePagination];
    }
}

- (NSInteger)totalPages {
    if (self.pageSize <= 0) return 1;
    NSInteger count = self.filteredItems.count;
    NSInteger pages = (count + self.pageSize - 1) / self.pageSize;
    return MAX(pages, 1);
}

- (void)updatePagination {
    NSInteger totalPages = [self totalPages];
    if (self.currentPage >= totalPages) self.currentPage = MAX(totalPages - 1, 0);
    [self updateDisplayedItems];
    self.pageLabel.text = [NSString stringWithFormat:@"第 %ld/%ld 页  共 %ld", (long)(self.currentPage + 1), (long)totalPages, (long)self.filteredItems.count];
    self.prevPageButton.enabled = self.currentPage > 0;
    self.nextPageButton.enabled = self.currentPage + 1 < totalPages;
    [self.tableView reloadData];
}

- (void)updateDisplayedItems {
    [self.displayItems removeAllObjects];
    NSInteger start = self.currentPage * self.pageSize;
    NSInteger end = MIN(start + self.pageSize, self.filteredItems.count);
    if (start < end) {
        [self.displayItems addObjectsFromArray:[self.filteredItems subarrayWithRange:NSMakeRange(start, end - start)]];
    }
}

- (void)applyFilterSettingsAndRefresh {

    [self applyFilterSettings];
    [self updateFilterSummary];
    self.currentPage = 0;
    [self updatePagination];
}

- (void)applyFilterSettings {
    [self.filteredItems removeAllObjects];
    PointerFilterSettings *settings = self.filterSettings;
    BOOL requiresValidation = settings.onlyValid || settings.valueEqualsEnabled;
    if (requiresValidation) {
        [self validateItems:self.allItems updateValue:YES];
    }
    
    for (PointerChainItem *item in self.allItems) {
        if (settings.moduleKeyword.length > 0) {
            if ([item.moduleName rangeOfString:settings.moduleKeyword options:NSCaseInsensitiveSearch].location == NSNotFound) {
                continue;
            }
        }
        if (settings.minLevelEnabled && item.level < settings.minLevel) continue;
        if (settings.maxLevelEnabled && item.level > settings.maxLevel) continue;
        if (settings.maxOffsetEnabled) {
            uint64_t maxOffset = 0;
            for (NSNumber *n in item.offsets) {
                uint64_t v = llabs((long long)n.longLongValue);
                if (v > maxOffset) maxOffset = v;
            }
            if (maxOffset > settings.maxOffset) continue;
        }
        if (settings.onlyValid) {
            if (!item.hasValidation || !item.isValid) continue;
        }
        if (settings.valueEqualsEnabled) {
            if (!item.hasValidation || item.finalValue != settings.valueEquals) continue;
        }
        [self.filteredItems addObject:item];
    }
}

- (NSString *)summaryPrefix {
    NSMutableArray<NSString *> *bits = [NSMutableArray array];

    if (self.compareHint.length) [bits addObject:self.compareHint];
    if (self.compareInfo.length) [bits addObject:self.compareInfo];
    if (self.actionInfo.length)  [bits addObject:self.actionInfo];

    return bits.count ? [[bits componentsJoinedByString:@"    "] stringByAppendingString:@"    "] : @"";
}

- (NSUInteger)validItemCount {
    NSUInteger n = 0;

    for (PointerChainItem *item in self.allItems) {
        if (item.isValid)
            n++;
    }
    return n;
}

- (void)updateFilterSummary {
    PointerFilterSettings *s = self.filterSettings;

    if (self.allItems.count == 0) {
        self.filterSummaryLabel.text = @"没有结果：点“加载”选历史结果，或先回上一页扫描一次";
        return;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (s.moduleKeyword.length > 0) [parts addObject:[NSString stringWithFormat:@"模块=%@", s.moduleKeyword]];
    if (s.minLevelEnabled || s.maxLevelEnabled) {
        NSString *minStr = s.minLevelEnabled ? [NSString stringWithFormat:@"%ld", (long)s.minLevel] : @"-";
        NSString *maxStr = s.maxLevelEnabled ? [NSString stringWithFormat:@"%ld", (long)s.maxLevel] : @"-";
        [parts addObject:[NSString stringWithFormat:@"层级=%@~%@", minStr, maxStr]];
    }
    if (s.maxOffsetEnabled) [parts addObject:[NSString stringWithFormat:@"偏移<=0x%llX", s.maxOffset]];
    if (s.valueEqualsEnabled) [parts addObject:[NSString stringWithFormat:@"值=0x%llX", s.valueEquals]];
    if (s.onlyValid) [parts addObject:@"仅有效"];
    if (parts.count == 0) {
        self.filterSummaryLabel.text = [NSString stringWithFormat:
            @"%@共 %lu 条 / 有效 %lu / 显示 %lu    筛选：无",
            [self summaryPrefix],
            (unsigned long)self.allItems.count,
            (unsigned long)[self validItemCount],
            (unsigned long)self.filteredItems.count];
    } else {
        self.filterSummaryLabel.text = [NSString stringWithFormat:
            @"%@共 %lu 条 / 有效 %lu / 显示 %lu    筛选：%@",
            [self summaryPrefix],
            (unsigned long)self.allItems.count,
            (unsigned long)[self validItemCount],
            (unsigned long)self.filteredItems.count,
            [parts componentsJoinedByString:@" | "]];
    }
}

- (void)saveFilterSettings:(PointerFilterSettings *)settings {
    if (!settings) return;
    NSDictionary *dict = @{
        @"moduleKeyword": settings.moduleKeyword ?: @"",
        @"minLevelEnabled": @(settings.minLevelEnabled),
        @"minLevel": @(settings.minLevel),
        @"maxLevelEnabled": @(settings.maxLevelEnabled),
        @"maxLevel": @(settings.maxLevel),
        @"maxOffsetEnabled": @(settings.maxOffsetEnabled),
        @"maxOffset": @(settings.maxOffset),
        @"onlyValid": @(settings.onlyValid),
        @"valueEqualsEnabled": @(settings.valueEqualsEnabled),
        @"valueEquals": @(settings.valueEquals)
    };
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"PointerFilterSettings"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (PointerFilterSettings *)loadSavedFilterSettings {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"PointerFilterSettings"];
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    PointerFilterSettings *settings = [[PointerFilterSettings alloc] init];
    settings.moduleKeyword = dict[@"moduleKeyword"] ?: @"";
    settings.minLevelEnabled = [dict[@"minLevelEnabled"] boolValue];
    settings.minLevel = [dict[@"minLevel"] integerValue];
    settings.maxLevelEnabled = [dict[@"maxLevelEnabled"] boolValue];
    settings.maxLevel = [dict[@"maxLevel"] integerValue];
    settings.maxOffsetEnabled = [dict[@"maxOffsetEnabled"] boolValue];
    settings.maxOffset = [dict[@"maxOffset"] unsignedLongLongValue];
    settings.onlyValid = [dict[@"onlyValid"] boolValue];
    settings.valueEqualsEnabled = [dict[@"valueEqualsEnabled"] boolValue];
    settings.valueEquals = [dict[@"valueEquals"] unsignedLongLongValue];
    return settings;
}

- (PointerChainItem *)buildItemFromRoot:(PointerChainNode *)root {
    PointerChainItem *item = [[PointerChainItem alloc] init];
    item.root = root;
    item.moduleName = root.moduleName ?: @"";
    item.baseOffset = root.address;
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray array];
    PointerChainNode *curr = root;
    while (curr) {
        if (curr.next != nil || curr.offset != 0) {
            [offsets addObject:@(curr.offset)];
        }
        curr = curr.next;
    }
    item.offsets = offsets;
    item.level = offsets.count;
    item.hasValidation = NO;
    item.isValid = NO;
    item.finalAddress = 0;
    item.finalValue = 0;
    return item;
}

- (uint64_t)moduleBaseForName:(NSString *)moduleName cache:(NSMutableDictionary<NSString *, NSNumber *> *)cache {
    if (moduleName.length == 0) return 0;
    NSNumber *cached = cache[moduleName];
    if (cached) return cached.unsignedLongLongValue;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *imagePath = [NSString stringWithUTF8String:name];
        if ([imagePath hasSuffix:moduleName] || [imagePath.lastPathComponent isEqualToString:moduleName]) {
            const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            uint64_t base = (uint64_t)header;
            cache[moduleName] = @(base);
            return base;
        }
    }
    cache[moduleName] = @(0);
    return 0;
}

- (void)validateItems:(NSArray<PointerChainItem *> *)items updateValue:(BOOL)updateValue {
    if (items.count == 0) return;
    NSMutableDictionary<NSString *, NSNumber *> *moduleBaseCache = [NSMutableDictionary dictionary];
    for (PointerChainItem *item in items) {
        uint64_t moduleBase = [self moduleBaseForName:item.moduleName cache:moduleBaseCache];
        if (moduleBase == 0) {
            item.hasValidation = YES;
            item.isValid = NO;
            item.finalAddress = 0;
            if (updateValue) item.finalValue = 0;
            continue;
        }
        uint64_t ptrAddr = moduleBase + item.baseOffset;
        BOOL valid = YES;
        size_t outSize = 0;
        for (NSNumber *offsetNum in item.offsets) {
            uint64_t ptrValue = 0;
            if (!SSMemoryRead(ptrAddr, &ptrValue, 8, &outSize) || outSize != 8) {
                valid = NO;
                break;
            }
            ptrAddr = ptrValue + offsetNum.longLongValue;
        }
        if (!valid) {
            item.hasValidation = YES;
            item.isValid = NO;
            item.finalAddress = 0;
            if (updateValue) item.finalValue = 0;
            continue;
        }
        item.hasValidation = YES;
        item.isValid = YES;
        item.finalAddress = ptrAddr;
        if (updateValue) {
            uint64_t finalValue = 0;
            if (SSMemoryRead(ptrAddr, &finalValue, 8, &outSize) && outSize == 8) {
                item.finalValue = finalValue;
            } else {
                item.finalValue = 0;
                item.isValid = NO;
            }
        }
    }
}


- (NSArray<PointerChainItem *> *)parseItemsFromContent:(NSString *)content {
    NSMutableArray<PointerChainItem *> *items = [NSMutableArray array];
    NSArray *lines = [content componentsSeparatedByString:@"\n"];

    for (NSString *line in lines) {
        if (line.length == 0) continue;

        // Format: [Module + BaseOffset] -> +Offset1 -> +Offset2
        NSArray *components = [line componentsSeparatedByString:@" -> "];
        if (components.count < 1) continue;

        NSString *basePart = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!([basePart hasPrefix:@"["] && [basePart hasSuffix:@"]"])) continue;

        NSString *content2 = [basePart substringWithRange:NSMakeRange(1, basePart.length - 2)];
        NSRange plusRange = [content2 rangeOfString:@"+" options:NSBackwardsSearch];
        if (plusRange.location == NSNotFound) continue;

        NSString *moduleName = [[content2 substringToIndex:plusRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *baseOffsetStr = [[content2 substringFromIndex:plusRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        uint64_t baseOffset = strtoull([baseOffsetStr UTF8String], NULL, 16);

        PointerChainNode *root = [[PointerChainNode alloc] init];
        root.moduleName = moduleName;
        root.isBase = YES;
        root.moduleBase = 0;
        root.address = baseOffset;

        PointerChainNode *current = root;

        for (NSUInteger i = 1; i < components.count; i++) {
            NSString *offsetPart = [components[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([offsetPart hasPrefix:@"+"]) {
                offsetPart = [offsetPart substringFromIndex:1];
            }
            current.offset = strtoll([offsetPart UTF8String], NULL, 16);

            if (i < components.count - 1) {
                PointerChainNode *next = [[PointerChainNode alloc] init];
                current.next = next;
                current = next;
            }
        }

        [items addObject:[self buildItemFromRoot:root]];
    }
    return items;
}

- (NSArray<PointerChainItem *> *)itemsFromFile:(NSString *)path {
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];

    if (!content)
        return @[];

    return [self parseItemsFromContent:content];
}

- (void)loadResultsFromFile:(NSString *)path {
    [LoggingService log:@"开始从文本文件读取数据: %@", path];
    
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        [LoggingService log:@"无法读取文件内容"];
        return;
    }
    
    self.allItems = [[self parseItemsFromContent:content] mutableCopy];
    [self applyFilterSettingsAndRefresh];
    [LoggingService log:@"加载完成，共 %lu 条数据", (unsigned long)self.allItems.count];
}

- (void)readButtonTapped {
    [LoggingService log:@"点击了读取按钮，开始读取指针链的值..."];
    [self validateItems:self.allItems updateValue:YES];

    NSUInteger valid = 0;
    PointerChainItem *sample = nil;

    for (PointerChainItem *item in self.allItems) {
        if (item.isValid) {
            valid++;
            if (!sample)
                sample = item;
        }
    }

    if (sample) {
        self.actionInfo = [NSString stringWithFormat:
            @"读取：已刷新 %lu 条的值（例 %@+0x%llX = 0x%llX / %llu）",
            (unsigned long)valid, sample.moduleName,
            (unsigned long long)sample.baseOffset,
            (unsigned long long)sample.finalValue,
            (unsigned long long)sample.finalValue];
    } else {
        self.actionInfo = @"读取：没有有效的链可读";
    }

    [LoggingService log:@"[筛选] %@", self.actionInfo];

    [self applyFilterSettingsAndRefresh];
}

- (void)backButtonTapped {
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.displayItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    }
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = IMGUI_TEXT;
    cell.textLabel.font = [UIFont fontWithName:@"Courier" size:12];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    cell.detailTextLabel.numberOfLines = 0;
    
    PointerChainItem *item = self.displayItems[indexPath.row];
    BOOL expanded = [self.expandedItems containsObject:item];
    
    NSString *baseStr = [NSString stringWithFormat:@"[%@ + 0x%llX]", item.moduleName, item.baseOffset];
    NSString *levelStr = [NSString stringWithFormat:@"层级:%ld", (long)item.level];
    NSString *statusStr = item.hasValidation ? (item.isValid ? @"有效" : @"断链") : @"未校验";
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@  %@", baseStr, levelStr, statusStr];
    
    NSMutableString *offsetStr = [NSMutableString string];
    if (item.offsets.count == 0) {
        [offsetStr appendString:@"偏移:无"];
    } else {
        [offsetStr appendString:@"偏移: "];
        for (NSUInteger i = 0; i < item.offsets.count; i++) {
            NSNumber *num = item.offsets[i];
            [offsetStr appendFormat:@"+0x%llX", (uint64_t)num.longLongValue];
            if (i + 1 < item.offsets.count) [offsetStr appendString:@" -> "];
        }
    }
    
    if (expanded) {
        NSMutableString *detail = [NSMutableString stringWithString:offsetStr];
        if (item.hasValidation) {
            [detail appendFormat:@"\n地址:0x%llX  值:0x%llX", item.finalAddress, item.finalValue];
        } else {
            [detail appendString:@"\n地址:--  值:--"];
        }
        cell.detailTextLabel.text = detail;
    } else {
        cell.detailTextLabel.text = offsetStr;
    }
    
    UIButton *expandButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [expandButton setTitle:(expanded ? @"▾" : @"▸") forState:UIControlStateNormal];
    [expandButton setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
    expandButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    expandButton.tag = indexPath.row;
    [expandButton addTarget:self action:@selector(toggleExpandTapped:) forControlEvents:UIControlEventTouchUpInside];
    [expandButton sizeToFit];
    cell.accessoryView = expandButton;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self toggleExpandForRow:indexPath.row];
}

- (void)toggleExpandTapped:(UIButton *)sender {
    [self toggleExpandForRow:sender.tag];
}

- (void)toggleExpandForRow:(NSInteger)row {
    if (row < 0 || row >= self.displayItems.count) return;
    PointerChainItem *item = self.displayItems[row];
    if ([self.expandedItems containsObject:item]) {
        [self.expandedItems removeObject:item];
    } else {
        [self.expandedItems addObject:item];
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
