#import "UI/Dialogs/FuzzySearchDialog.h"
#import "Services/LogService.h"
#import "Modules/Scanner/Scanner.h"

@interface SSHelpPopViewController ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *dataTypeContainer;
@property (nonatomic, strong) NSMutableArray<UIButton *> *typeButtons;
@property (nonatomic, assign) NSInteger selectedTypeIndex;

@end

@implementation SSHelpPopViewController

+ (instancetype)helpPopViewController {
    return [[self alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
}

- (void)setupUI {
    // 半透明背景
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    
    // 内容视图
    self.contentView = [[UIView alloc] init];
    self.contentView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];  // RGB(128,128,128)
    [self.view addSubview:self.contentView];
    
    // 设置内容视图约束
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.contentView.widthAnchor constraintEqualToConstant:250],
        [self.contentView.heightAnchor constraintEqualToConstant:150]
    ]];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"模糊搜索";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:titleLabel];
    
    // 创建数据类型选择容器
    self.dataTypeContainer = [[UIView alloc] init];
    self.dataTypeContainer.backgroundColor = [UIColor whiteColor];
    self.dataTypeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.dataTypeContainer];

    // 设置数据类型容器约束
    [NSLayoutConstraint activateConstraints:@[
        [self.dataTypeContainer.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [self.dataTypeContainer.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.dataTypeContainer.widthAnchor constraintEqualToConstant:250],
        [self.dataTypeContainer.heightAnchor constraintEqualToConstant:30]
    ]];

    // 初始化按钮数组
    self.typeButtons = [NSMutableArray array];
    NSArray *types = @[@"i8", @"i16", @"i32", @"i64", @"f32", @"f64"];
    CGFloat buttonWidth = 250.0f / types.count;  // 容器宽度除以按钮数量

    // 创建类型按钮
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        [button setTitle:types[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
        button.titleLabel.font = [UIFont systemFontOfSize:12];
        button.backgroundColor = [UIColor whiteColor];
        [button addTarget:self action:@selector(typeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        button.frame = CGRectMake(buttonWidth * i, 0, buttonWidth, 30);
        [self.dataTypeContainer addSubview:button];
        [self.typeButtons addObject:button];
        
        // 添加右边框（除了最后一个按钮）
        if (i < types.count - 1) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(buttonWidth * (i + 1), 0, 1, 30)];
            separator.backgroundColor = [UIColor colorWithRed:200/255.0 green:200/255.0 blue:200/255.0 alpha:1.0];
            [self.dataTypeContainer addSubview:separator];
        }
    }

    // 根据当前数据类型选择对应的按钮
    NSInteger buttonIndex = 0;
    switch (当前数据类型) {
        case SearchDataTypeU8:
            buttonIndex = 0;
            break;
        case SearchDataTypeI16:
            buttonIndex = 1;
            break;
        case SearchDataTypeI32:
            buttonIndex = 2;
            break;
        case SearchDataTypeI64:
            buttonIndex = 3;
            break;
        case SearchDataTypeF32:
            buttonIndex = 4;
            break;
        case SearchDataTypeF64:
            buttonIndex = 5;
            break;
        default:
            buttonIndex = 2;
            break;
    }
    
    // 确保索引在范围内
    if (buttonIndex < self.typeButtons.count) {
        [self typeButtonTapped:self.typeButtons[buttonIndex]];
    }
    
    // 添加搜索按钮
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [searchButton setTitle:@"搜索" forState:UIControlStateNormal];
    searchButton.backgroundColor = [UIColor systemBlueColor];
    [searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.contentView addSubview:searchButton];
    
    // 设置约束
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 标题约束
        [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:15],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        
        // 搜索按钮约束
        [searchButton.topAnchor constraintEqualToAnchor:self.dataTypeContainer.bottomAnchor constant:20],
        [searchButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [searchButton.widthAnchor constraintEqualToConstant:120],
        [searchButton.heightAnchor constraintEqualToConstant:40]
    ]];
    
    // 添加搜索按钮点击事件
    [searchButton addTarget:self action:@selector(searchButtonTapped) forControlEvents:UIControlEventTouchUpInside];
}

- (void)closeButtonTapped {
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    }];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch.view == self.view) {
        [self closeButtonTapped];
    }
}

// 修改 searchButtonTapped 方法
- (void)searchButtonTapped {
    [LoggingService log:@"开始执行模糊搜索"];
    
    // 创建搜索目标值
    数值 searchValue = {0};
    数据类型 dataType;
    
    // 根据选中的数据类型设置默认值
    switch (self.selectedTypeIndex) {
        case 0: // i8
            dataType = 类型_字节;
            [LoggingService log:@"使用i8类型搜索"];
            break;
        case 1: // i16
            dataType = 类型_短整数;
            [LoggingService log:@"使用i16类型搜索"];
            break;
        case 2: // i32
            dataType = 类型_整数;
            [LoggingService log:@"使用i32类型搜索"];
            break;
        case 3: // i64
            dataType = 类型_长整数;
            [LoggingService log:@"使用i64类型搜索"];
            break;
        case 4: // f32
            dataType = 类型_浮点;
            [LoggingService log:@"使用f32类型搜索"];
            break;
        case 5: // f64
            dataType = 类型_双精度;
            [LoggingService log:@"使用f64类型搜索"];
            break;
        default:
            dataType = 类型_整数;
            break;
    }
    
    [LoggingService log:@"当前搜索模式: %d", 当前搜索模式];
    
    // 第一次搜索,直接执行搜索模式二
    [LoggingService log:@"执行第一次模糊搜索"];
    搜索模式二(searchValue, dataType, 未知);
    
    // 关闭弹窗
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    }];
    
    //[LoggingService log:@"模糊搜索弹窗已关闭"];
}

// 添加类型按钮点击方法
- (void)typeButtonTapped:(UIButton *)sender {
    // 更新所有按钮状态
    for (UIButton *button in self.typeButtons) {
        button.selected = (button == sender);
        button.backgroundColor = button.selected ? 
            [UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0] : 
            [UIColor whiteColor];
    }
    self.selectedTypeIndex = sender.tag;
    
    // 根据选择的类型设置当前数据类型
    switch (sender.tag) {
        case 0:  // i8
            [ScannerState shared].currentDataType = SearchDataTypeU8;
            break;
        case 1:  // i16
            [ScannerState shared].currentDataType = SearchDataTypeI16;
            break;
        case 2:  // i32
            [ScannerState shared].currentDataType = SearchDataTypeI32;
            break;
        case 3:  // i64
            [ScannerState shared].currentDataType = SearchDataTypeI64;
            break;
        case 4:  // f32
            [ScannerState shared].currentDataType = SearchDataTypeF32;
            break;
        case 5:  // f64
            [ScannerState shared].currentDataType = SearchDataTypeF64;
            break;
        default:
            [ScannerState shared].currentDataType = SearchDataTypeI32;
            break;
    }
    
    [LoggingService log:@"数据类型已更新为: %d", 当前数据类型];
}

@end 