#import "UI/Dialogs/OptionsMenu.h"

@interface SSCustomMenuView ()

@property (nonatomic, strong) NSArray<NSString *> *options;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIVisualEffectView *blurView;

@end

@implementation SSCustomMenuView

- (instancetype)initWithOptions:(NSArray<NSString *> *)options {
    self = [super init];
    if (self) {
        self.options = options;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    
    // 创建模糊效果视图
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.layer.cornerRadius = 10;
    self.blurView.clipsToBounds = YES;
    [self addSubview:self.blurView];
    
    // 创建容器视图
    self.containerView = [[UIView alloc] init];
    self.containerView.backgroundColor = [UIColor clearColor];
    [self.blurView.contentView addSubview:self.containerView];
    
    // 创建选项按钮
    CGFloat buttonHeight = 44;
    CGFloat totalHeight = buttonHeight * self.options.count;
    CGFloat menuWidth = 180;
    
    for (NSInteger i = 0; i < self.options.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = i;
        [button setTitle:self.options[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:16];
        button.frame = CGRectMake(0, buttonHeight * i, menuWidth, buttonHeight);
        [button addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        // 添加分隔线（除了最后一个按钮）
        if (i < self.options.count - 1) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(10, buttonHeight * (i + 1) - 0.5, menuWidth - 20, 0.5)];
            separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
            [self.containerView addSubview:separator];
        }
        
        [self.containerView addSubview:button];
    }
    
    self.containerView.frame = CGRectMake(0, 0, menuWidth, totalHeight);
    self.blurView.frame = self.containerView.frame;
}

- (void)showFromPoint:(CGPoint)point inView:(UIView *)view {
    self.frame = view.bounds;
    [view addSubview:self];
    
    // 计算菜单位置
    CGFloat menuWidth = self.containerView.frame.size.width;
    CGFloat menuHeight = self.containerView.frame.size.height;
    
    // 计算中心位置
    CGFloat x = (view.bounds.size.width - menuWidth) / 2;
    CGFloat y = (view.bounds.size.height - menuHeight) / 2;
    
    // 设置最终位置
    self.blurView.frame = CGRectMake(x, y, menuWidth, menuHeight);
    self.containerView.frame = CGRectMake(0, 0, menuWidth, menuHeight);
    
    // 添加动画效果
    self.blurView.alpha = 0;
    self.blurView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    [UIView animateWithDuration:0.2 animations:^{
        self.blurView.alpha = 1;
        self.blurView.transform = CGAffineTransformIdentity;
    }];
}

- (void)optionTapped:(UIButton *)sender {
    if (self.onOptionSelected) {
        self.onOptionSelected(sender.tag);
    }
    [self dismiss];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.blurView.alpha = 0;
        self.blurView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    if (!CGRectContainsPoint(self.blurView.frame, point)) {
        [self dismiss];
    }
}

@end 