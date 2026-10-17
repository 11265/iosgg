#import "UI/Components/AccessHeaderView.h"
#import "UI/Components/ThemeConfig.h"

@interface AccessHeaderView ()

@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *slotLabel;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UIButton *moreButton;

@end

@implementation AccessHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];

    self.statusDot = [[UIView alloc] init];
    self.statusDot.layer.cornerRadius = 4;
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.statusDot];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [AppTheme regularFont:12];
    self.statusLabel.textColor = [AppTheme textColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.statusLabel];

    self.slotLabel = [[UILabel alloc] init];
    self.slotLabel.font = [AppTheme monospaceFont:10];
    self.slotLabel.textColor = [AppTheme textDisabledColor];
    self.slotLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.slotLabel];

    self.addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.addButton setTitle:@"＋" forState:UIControlStateNormal];
    [self.addButton setTitleColor:[AppTheme textHighlightColor] forState:UIControlStateNormal];
    self.addButton.titleLabel.font = [AppTheme regularFont:22];
    self.addButton.accessibilityLabel = @"添加访问点";
    self.addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.addButton];

    self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.moreButton setTitle:@"⋯" forState:UIControlStateNormal];
    [self.moreButton setTitleColor:[AppTheme textColor] forState:UIControlStateNormal];
    self.moreButton.titleLabel.font = [AppTheme regularFont:20];
    self.moreButton.accessibilityLabel = @"更多";
    self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.moreButton];

    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = [AppTheme borderColor];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:separator];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusDot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:8],
        [self.statusDot.heightAnchor constraintEqualToConstant:8],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:6],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [self.slotLabel.leadingAnchor constraintEqualToAnchor:self.statusLabel.trailingAnchor constant:8],
        [self.slotLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.slotLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.addButton.leadingAnchor constant:-8],

        [self.moreButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        [self.moreButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.moreButton.widthAnchor constraintEqualToConstant:44],
        [self.moreButton.heightAnchor constraintEqualToConstant:44],

        [self.addButton.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-2],
        [self.addButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.addButton.widthAnchor constraintEqualToConstant:44],
        [self.addButton.heightAnchor constraintEqualToConstant:44],

        [separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5]
    ]];
}

- (void)updateWithRunning:(BOOL)running slotCount:(NSInteger)slotCount slotLimit:(NSInteger)slotLimit {
    self.statusDot.backgroundColor = running
        ? [UIColor colorWithRed:0.20f green:0.80f blue:0.40f alpha:1.0f]
        : [AppTheme textDisabledColor];
    self.statusLabel.text = running ? @"运行中" : @"已停止";
    self.statusLabel.textColor = running ? [AppTheme textColor] : [AppTheme textDisabledColor];

    self.slotLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)slotCount, (long)slotLimit];
    self.slotLabel.textColor = (slotLimit > 0 && slotCount >= slotLimit)
        ? [AppTheme errorColor]
        : [AppTheme textDisabledColor];

    // 槽满时仍允许点击，由页面给出解释，而不是静默无响应
    self.addButton.alpha = (slotLimit > 0 && slotCount >= slotLimit) ? 0.35f : 1.0f;
}

- (void)addTapped {
    [self.delegate accessHeaderDidTapAdd:self];
}

- (void)moreTapped {
    [self.delegate accessHeaderDidTapMore:self];
}

@end
