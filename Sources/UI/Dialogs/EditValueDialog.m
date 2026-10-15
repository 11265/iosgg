#import "UI/Dialogs/EditValueDialog.h"
#import "Services/LogService.h"
#import <objc/runtime.h>
#import <mach/mach.h>
#import "UI/Pages/SearchPage.h"
#import "UI/Pages/TracePage.h"
#import "UI/Pages/TracePage+Debugger.h"
#import "UI/Pages/MemoryPage.h"
#import "UI/Pages/RecordPage.h"
#import "UI/Components/FloatingWindow.h"

NSString *const kModifyValueNotification = @"ModifyValueNotification";

@interface SSModifyPopViewController ()

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *rightContainerView;
@property (nonatomic, strong) UICollectionView *buttonCollectionView;
@property (nonatomic, copy) NSArray *buttonTitles;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *typeLabel;



@end

@implementation SSModifyPopViewController

+ (instancetype)modifyPopViewController {
    SSModifyPopViewController *vc = [[SSModifyPopViewController alloc] init];
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 设置背景半透明
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    
    // 创建容器视图
    self.containerView = [[UIView alloc] init];
    self.containerView.backgroundColor = [UIColor colorWithRed:240/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
    self.containerView.layer.cornerRadius = 10;
    [self.view addSubview:self.containerView];
    
    // 设置容器视图约束
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.containerView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.containerView.widthAnchor constraintEqualToConstant:180]
        // Removed fixed height to allow auto-sizing
    ]];
    
    // 创建左侧容器
    UIView *leftContainerView = [[UIView alloc] init];
    leftContainerView.backgroundColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0];
    [self.containerView addSubview:leftContainerView];
    
    // 创建地址标签
    self.addressLabel = [[UILabel alloc] init];
    self.addressLabel.textColor = [UIColor whiteColor];
    self.addressLabel.font = [UIFont systemFontOfSize:14];
    [leftContainerView addSubview:self.addressLabel];
    
    // 创建类型标签
    self.typeLabel = [[UILabel alloc] init];
    self.typeLabel.textColor = [UIColor whiteColor];
    self.typeLabel.font = [UIFont systemFontOfSize:14];
    [leftContainerView addSubview:self.typeLabel];
    
    // 设置约束
    leftContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 左侧容器约束
        [leftContainerView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [leftContainerView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [leftContainerView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [leftContainerView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor],
        
        // 地址标签约束
        [self.addressLabel.topAnchor constraintEqualToAnchor:leftContainerView.topAnchor constant:10],
        [self.addressLabel.centerXAnchor constraintEqualToAnchor:leftContainerView.centerXAnchor],
        [self.addressLabel.leadingAnchor constraintEqualToAnchor:leftContainerView.leadingAnchor constant:10],
        [self.addressLabel.trailingAnchor constraintEqualToAnchor:leftContainerView.trailingAnchor constant:-10],
        
        // 类型标签约束
        [self.typeLabel.topAnchor constraintEqualToAnchor:self.addressLabel.bottomAnchor constant:5],
        [self.typeLabel.centerXAnchor constraintEqualToAnchor:leftContainerView.centerXAnchor],
        [self.typeLabel.leadingAnchor constraintEqualToAnchor:leftContainerView.leadingAnchor constant:10],
        [self.typeLabel.trailingAnchor constraintEqualToAnchor:leftContainerView.trailingAnchor constant:-10],
    ]];
    
    // 创建按钮容器
    UIView *buttonContainer = [[UIView alloc] init];
    [leftContainerView addSubview:buttonContainer];
    buttonContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 创建添加到记录按钮
    UIButton *addToRecordButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [addToRecordButton setTitle:@"添加到记录" forState:UIControlStateNormal];
    [addToRecordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    addToRecordButton.backgroundColor = [UIColor systemGreenColor];
    [addToRecordButton addTarget:self action:@selector(addToRecordButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:addToRecordButton];

    // 创建复制地址按钮
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyButton setTitle:@"复制地址" forState:UIControlStateNormal];
    [copyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyButton.backgroundColor = [UIColor systemGrayColor];
    [copyButton addTarget:self action:@selector(copyAddressButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:copyButton];
    
    // 创建是什么读取按钮
    UIButton *whatAccessButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [whatAccessButton setTitle:@"是什么读取" forState:UIControlStateNormal];
    [whatAccessButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    whatAccessButton.backgroundColor = [UIColor systemPurpleColor];
    [whatAccessButton addTarget:self action:@selector(whatAccessButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:whatAccessButton];
    
    // 创建是什么写入按钮
    UIButton *whatWriteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [whatWriteButton setTitle:@"是什么写入" forState:UIControlStateNormal];
    [whatWriteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    whatWriteButton.backgroundColor = [UIColor systemIndigoColor];
    [whatWriteButton addTarget:self action:@selector(whatWriteButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:whatWriteButton];
    
    // 创建复制数值按钮
    UIButton *copyValueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyValueButton setTitle:@"复制数值" forState:UIControlStateNormal];
    [copyValueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyValueButton.backgroundColor = [UIColor systemGrayColor];
    [copyValueButton addTarget:self action:@selector(copyValueButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:copyValueButton];
    
    // 创建查看内存按钮
    UIButton *viewMemoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [viewMemoryButton setTitle:@"查看内存" forState:UIControlStateNormal];
    [viewMemoryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    viewMemoryButton.backgroundColor = [UIColor darkGrayColor];
    [viewMemoryButton addTarget:self action:@selector(viewMemoryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:viewMemoryButton];
    
    // 设置按钮约束
    addToRecordButton.translatesAutoresizingMaskIntoConstraints = NO;
    copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    whatAccessButton.translatesAutoresizingMaskIntoConstraints = NO;
    whatWriteButton.translatesAutoresizingMaskIntoConstraints = NO;
    copyValueButton.translatesAutoresizingMaskIntoConstraints = NO;
    viewMemoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 设置按钮容器约束
    [NSLayoutConstraint activateConstraints:@[
        // 按钮容器约束
        [buttonContainer.topAnchor constraintEqualToAnchor:self.typeLabel.bottomAnchor constant:10],
        [buttonContainer.leadingAnchor constraintEqualToAnchor:leftContainerView.leadingAnchor constant:10],
        [buttonContainer.trailingAnchor constraintEqualToAnchor:leftContainerView.trailingAnchor constant:-10],
        [buttonContainer.bottomAnchor constraintEqualToAnchor:copyValueButton.bottomAnchor], // Hug the bottom content
        
        [leftContainerView.bottomAnchor constraintEqualToAnchor:buttonContainer.bottomAnchor constant:10], // Add padding below button container
        
        // 添加到记录按钮约束（第一个）
        [addToRecordButton.topAnchor constraintEqualToAnchor:buttonContainer.topAnchor],
        [addToRecordButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [addToRecordButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [addToRecordButton.heightAnchor constraintEqualToConstant:34],
        
        // 是什么访问按钮约束（第二个）
        [whatAccessButton.topAnchor constraintEqualToAnchor:addToRecordButton.bottomAnchor constant:5],
        [whatAccessButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [whatAccessButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [whatAccessButton.heightAnchor constraintEqualToConstant:34],
        
        // 是什么写入按钮约束（第三个）
        [whatWriteButton.topAnchor constraintEqualToAnchor:whatAccessButton.bottomAnchor constant:5],
        [whatWriteButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [whatWriteButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [whatWriteButton.heightAnchor constraintEqualToConstant:34],
        
        // 查看内存按钮约束（第四个）
        [viewMemoryButton.topAnchor constraintEqualToAnchor:whatWriteButton.bottomAnchor constant:5],
        [viewMemoryButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [viewMemoryButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [viewMemoryButton.heightAnchor constraintEqualToConstant:34],
        
        // 复制地址按钮约束（第五个）
        [copyButton.topAnchor constraintEqualToAnchor:viewMemoryButton.bottomAnchor constant:5],
        [copyButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [copyButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [copyButton.heightAnchor constraintEqualToConstant:34],
        
        // 复制数值按钮约束（第六个）
        [copyValueButton.topAnchor constraintEqualToAnchor:copyButton.bottomAnchor constant:5],
        [copyValueButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [copyValueButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [copyValueButton.heightAnchor constraintEqualToConstant:34],
    ]];
    
    // 添加点击背景关闭的手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
    [self.view addGestureRecognizer:tapGesture];
    
    [LoggingService log:@"修改弹窗已初始化"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // 添加日志
    [LoggingService log:@"修改弹框显示 - 当前类型: %d", (int)self.dataType];
}

// modifyButtonTapped removed

- (void)copyAddressButtonTapped:(UIButton *)sender {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *addressString = [NSString stringWithFormat:@"0x%llX", self.address];
    pasteboard.string = addressString;
    [LoggingService log:@"存址复制: %@", addressString];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    if (!CGRectContainsPoint(self.containerView.frame, location)) {
        [self dismissSelf];
    }
}

- (void)dismissSelf {
    [LoggingService log:@"关闭修改弹窗"];
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
    [LoggingService log:@"修改弹窗已关闭"];
}

- (void)setAddress:(uint64_t)address {
    _address = address;
    self.addressLabel.text = [NSString stringWithFormat:@"地址: 0x%llX", address];
}

- (void)setDataType:(SearchDataType)dataType {
    _dataType = dataType;
    NSArray *types = @[@"i32", @"i64", @"f32", @"f64"];
    self.typeLabel.text = [NSString stringWithFormat:@"类型: %@", types[dataType]];
    [LoggingService log:@"设置数据类型: %d", (int)dataType];
}

- (void)whatAccessButtonTapped:(UIButton *)sender {
    [self startTrackingWithType:SSBreakpointTypeRead logMessage:@"准备跟踪读取: 0x%llX"];
}

- (void)whatWriteButtonTapped:(UIButton *)sender {
    [self startTrackingWithType:SSBreakpointTypeWrite logMessage:@"准备跟踪写入: 0x%llX"];
}

- (void)startTrackingWithType:(SSBreakpointType)type logMessage:(NSString *)logMsg {
    [LoggingService log:logMsg, self.address];
    [LoggingService log:@"[startTrackingWithType] self.address=0x%llX, type=%d", self.address, (int)type];
    
    // 取跟踪页面实例
    SSTrackPopViewController *trackVC = [SSTrackPopViewController trackPopViewController];
    
    // 如果调试器未启动，先启动调试器
    // 优先使用 SSDebugger 单例判断真实状态，而不是 trackVC 的状态
    SSDebugger *debugger = [SSDebugger sharedInstance];
    if (!debugger.isDebugging) {
        // 如果未启动，尝试通过 trackVC 启动（因为它封装了 pid 获取等逻辑）
        // 但为了保险，也可以直接调用 debugger
        [trackVC startDebugging];
        
        // 如果 trackVC 启动失败或者状态没更新，这里再次检查
        if (!debugger.isDebugging) {
             [LoggingService log:@"调试器启动失败，无法添加监视点"];
             return;
        }
    }
    
    [LoggingService log:@"[startTrackingWithType] 准备调用 addMemoryWatchpoint: 0x%llX", self.address];
    
    // 添加监视点
    [trackVC addMemoryWatchpoint:self.address size:4 type:type];  // 使用4字节作为监视大小
    
    // 提示用户已添加监视点
    [LoggingService log:@"已添加监视点: 0x%llX (Type: %d)", self.address, (int)type];
    
    // 显示跟踪页面 -> 实际上应该什么都不做，让用户留在原处，或者不需要显示trackVC
    // 因为现在是通过通知同步到访问页面了
    // [trackVC show]; 
    
    // 关闭当前弹窗
    [self dismissSelf];
}

- (void)copyValueButtonTapped:(UIButton *)sender {
    NSString *valueString;
    uint64_t memValue;
    mach_vm_size_t size = sizeof(uint64_t);
    mach_vm_address_t address = self.address;
    mach_vm_size_t outsize;
    mach_vm_read_overwrite(mach_task_self(), address, size, (mach_vm_address_t)&memValue, &outsize);
    
    // 根据数据类型正确读取和格式化值
    switch(self.dataType) {
        case SearchDataTypeI32: {
            int32_t value = (int32_t)memValue;
            valueString = [NSString stringWithFormat:@"%d", value];
            break;
        }
        case SearchDataTypeI64: {
            int64_t value = (int64_t)memValue;
            valueString = [NSString stringWithFormat:@"%lld", value];
            break;
        }
        case SearchDataTypeF32: {
            uint32_t truncatedValue = (uint32_t)memValue;  // 只取低32位
            float floatValue = *(float *)&truncatedValue;  // 正确转换为float
            valueString = [NSString stringWithFormat:@"%.6f", floatValue];
            break;
        }
        case SearchDataTypeF64: {
            double doubleValue = *(double *)&memValue;
            valueString = [NSString stringWithFormat:@"%.6f", doubleValue];
            break;
        }
        case SearchDataTypeU8: {
            uint8_t value = (uint8_t)memValue;
            valueString = [NSString stringWithFormat:@"%d", value];
            break;
        }
        case SearchDataTypeI16: {
            int16_t value = (int16_t)memValue;
            valueString = [NSString stringWithFormat:@"%d", value];
            break;
        }
        default:
            [LoggingService log:@"错误：未知的数据类型 %ld", (long)self.dataType];
            return;
    }
    
    if (valueString) {
        if (sender) {  // 如果是通过按钮调用的，则复制到剪贴板
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            pasteboard.string = valueString;
        }
        
        [LoggingService log:@"已更新值: %@ (类型: %d)", valueString, (int)self.dataType];
    } else {
        [LoggingService log:@"复制/更新数值失败"];
    }
}

- (void)viewMemoryButtonTapped:(UIButton *)sender {
    [LoggingService log:@"查看内存地址: 0x%llX", self.address];
    
    // 显示内存查看器
    FloatingWindow *floatingWindow = [FloatingWindow sharedInstance];
    
    // 先显示浮动窗口
    [floatingWindow show];
    
    // 延迟一帧再切换到内存页和设置地址
    dispatch_async(dispatch_get_main_queue(), ^{
        // 设置内存为当前中的标签页（索引2是内存页）
        floatingWindow.tabBarController.selectedIndex = 2;
        
        // 获取内存页控制器
        MemoryPages *memoryVC = (MemoryPages *)floatingWindow.tabBarController.viewControllers[2];
        
        // 跳转到指定地址
        [memoryVC jumpToAddress:self.address];
        
        // 关闭当前弹窗
        [self dismissSelf];
    });
}

- (void)addToRecordButtonTapped:(UIButton *)sender {
    FloatingWindow *floatingWindow = [FloatingWindow sharedInstance];
    RecordPage *recordPage = floatingWindow.recordViewController;
    
    if (recordPage) {
        NSString *typeStr = @"i32";
        switch (self.dataType) {
            case SearchDataTypeI32: typeStr = @"i32"; break;
            case SearchDataTypeI64: typeStr = @"i64"; break;
            case SearchDataTypeF32: typeStr = @"f32"; break;
            case SearchDataTypeF64: typeStr = @"f64"; break;
            default: typeStr = @"i32"; break;
        }
        
        NSDictionary *record = @{
            @"address": [NSString stringWithFormat:@"0x%llX", self.address],
            @"type": typeStr
        };
        
        [recordPage addAddressesToRecord:@[record]];
        [LoggingService log:@"已添加到记录: 0x%llX (%@)", self.address, typeStr];
        [self dismissSelf];
    } else {
        [LoggingService log:@"错误：无法获取记录页面实例"];
    }
}

@end 