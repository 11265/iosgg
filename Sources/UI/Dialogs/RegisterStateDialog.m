#import "UI/Dialogs/RegisterStateDialog.h"
#import "Modules/Debugger/SSDebugger.h"
#import "Services/LogService.h"

@interface SSRegisterCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation SSRegisterCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.nameLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        [self.contentView addSubview:self.nameLabel];
        
        self.valueLabel = [[UILabel alloc] init];
        self.valueLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.valueLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        [self.contentView addSubview:self.valueLabel];
        
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        [NSLayoutConstraint activateConstraints:@[
            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
            [self.nameLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.nameLabel.widthAnchor constraintEqualToConstant:60],
            
            [self.valueLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor constant:15],
            [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        ]];
    }
    return self;
}

@end

@interface SSRegisterPopupView () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) NSArray *registers;
@property (nonatomic, strong) NSArray *values;
@property (nonatomic, strong) UISegmentedControl *displayTypeSegment;
@property (nonatomic, assign) BOOL showHex;
@end

@implementation SSRegisterPopupView

+ (instancetype)sharedInstance {
    static SSRegisterPopupView *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        self.showHex = NO;
        
        // 创建容器视图
        self.containerView = [[UIView alloc] init];
        self.containerView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        [self addSubview:self.containerView];
        
        // 添加类型选择器
        self.displayTypeSegment = [[UISegmentedControl alloc] initWithItems:@[@"十进制", @"十六进制"]];
        self.displayTypeSegment.selectedSegmentIndex = 0;
        self.displayTypeSegment.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        [self.displayTypeSegment addTarget:self action:@selector(displayTypeChanged:) forControlEvents:UIControlEventValueChanged];
        [self.containerView addSubview:self.displayTypeSegment];
        
        // 添加关闭按钮
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
        [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        [closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.containerView addSubview:closeButton];
        
        // 创建表格视图
        self.tableView = [[UITableView alloc] init];
        self.tableView.delegate = self;
        self.tableView.dataSource = self;
        self.tableView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        self.tableView.separatorColor = [UIColor lightGrayColor];
        [self.tableView registerClass:[SSRegisterCell class] forCellReuseIdentifier:@"RegisterCell"];
        [self.containerView addSubview:self.tableView];
        
        // 设置约束
        self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
        
        [NSLayoutConstraint activateConstraints:@[
            // 容器视图约束
            [self.containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.containerView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.containerView.widthAnchor constraintEqualToConstant:300],
            [self.containerView.heightAnchor constraintEqualToConstant:300],
            
            // 类型选择器约束
            [self.displayTypeSegment.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:5],
            [self.displayTypeSegment.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:5],
            [self.displayTypeSegment.widthAnchor constraintEqualToConstant:160],
            [self.displayTypeSegment.heightAnchor constraintEqualToConstant:35],
            
            // 修改关闭按钮约束,让它靠右
            [closeButton.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:5],
            [closeButton.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-5],
            [closeButton.widthAnchor constraintEqualToConstant:60],
            [closeButton.heightAnchor constraintEqualToConstant:35],
            
            // 表格视图约束
            [self.tableView.topAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:5],
            [self.tableView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
            [self.tableView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
            [self.tableView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor],
        ]];
        
        // 初始化寄存器名称数组
        self.registers = @[@"x0", @"x1", @"x2", @"x3", @"x4", @"x5", @"x6", @"x7", 
                          @"x8", @"x9", @"x10", @"x11", @"x12", @"x13", @"x14", @"x15",
                          @"x16", @"x17", @"x18", @"x19", @"x20", @"x21", @"x22", @"x23",
                          @"x24", @"x25", @"x26", @"x27", @"x28", @"fp", @"lr", @"sp", @"pc"];
        
        // 添加背景点击手势
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
        [self addGestureRecognizer:tapGesture];
    }
    return self;
}

- (void)showInView:(UIView *)parentView {
    self.frame = parentView.bounds;
    [parentView addSubview:self];
    
    self.containerView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    self.alpha = 0;
    
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 1;
        self.containerView.transform = CGAffineTransformIdentity;
    }];
    
    [self updateRegisterValues];
}

- (void)updateRegisterValues {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    if (!debugger.isDebugging) {
        [LoggingService log:@"调试器未运行"];
        return;
    }
    
    // 获取指定指令地址的寄存器值
    NSDictionary *registers = [debugger getRegistersAtInstructionAddress:self.instructionAddress];
    if (!registers) {
        [LoggingService log:@"获取寄存器值失败"];
        return;
    }
    
    // 更新寄存器值
    NSMutableArray *values = [NSMutableArray array];
    for (NSString *regName in self.registers) {
        NSNumber *value = registers[regName];
        if (value) {
            if (self.showHex) {
                // 16进制格式
                [values addObject:[NSString stringWithFormat:@"0x%llx", value.longLongValue]];
            } else {
                // 10进制格式
                [values addObject:[NSString stringWithFormat:@"%lld", value.longLongValue]];
            }
        } else {
            [values addObject:@"--"];
        }
    }
    self.values = values;
    
    [self.tableView reloadData];
}

- (void)closeButtonTapped {
    [self dismiss];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    if (!CGRectContainsPoint(self.containerView.frame, location)) {
        [self dismiss];
    }
}

- (void)dismiss {
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 0;
        self.containerView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        self.containerView.transform = CGAffineTransformIdentity;
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.registers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SSRegisterCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RegisterCell"];
    
    cell.nameLabel.text = self.registers[indexPath.row];
    cell.valueLabel.text = self.values[indexPath.row];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

- (void)displayTypeChanged:(UISegmentedControl *)sender {
    self.showHex = sender.selectedSegmentIndex == 1;
    [self updateRegisterValues];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // 获取选中的寄存器值
    NSString *value = self.values[indexPath.row];
    
    // 创建粘贴板并复制
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = value;
    
    // 显示复制成功提示
    [self showCopySuccessHint];
    
    // 取消选中状态
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)showCopySuccessHint {
    UIView *hintView = [[UIView alloc] init];
    hintView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    hintView.layer.cornerRadius = 10;
    [self addSubview:hintView];
    
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"已复制";
    hintLabel.textColor = [UIColor whiteColor];
    hintLabel.font = [UIFont systemFontOfSize:14];
    [hintView addSubview:hintLabel];
    
    hintView.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [hintView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [hintView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [hintView.widthAnchor constraintEqualToConstant:80],
        [hintView.heightAnchor constraintEqualToConstant:40],
        
        [hintLabel.centerXAnchor constraintEqualToAnchor:hintView.centerXAnchor],
        [hintLabel.centerYAnchor constraintEqualToAnchor:hintView.centerYAnchor],
    ]];
    
    // 1.5秒后移除提示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            hintView.alpha = 0;
        } completion:^(BOOL finished) {
            [hintView removeFromSuperview];
        }];
    });
}

@end 