#import "UI/Components/AccessCell.h"
#import "UI/Components/ThemeConfig.h"
#import "Models/AccessRecord.h"
#import "Services/SSSymbolicator.h"

static NSDateFormatter *SSAccessTimeFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"HH:mm:ss"];
    });
    return formatter;
}

/// 视觉上仍是 52×24 的小胶囊，但把点击热区扩到 44pt 高
@interface SSAccessHitButton : UIButton
@end

@implementation SSAccessHitButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect bounds = self.bounds;
    CGFloat verticalInset = MAX(0, (44.0 - bounds.size.height) / 2.0);
    bounds = CGRectInset(bounds, -6, -verticalInset);
    return CGRectContainsPoint(bounds, point);
}

@end

@interface AccessCell ()

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIButton *typePill;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *symbolLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *chevronLabel;

@end

@implementation AccessCell

+ (NSString *)reuseIdentifier {
    return @"AccessCell";
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    self.containerView = [[UIView alloc] init];
    self.containerView.backgroundColor = [UIColor colorWithWhite:0.10f alpha:1.0f];
    self.containerView.layer.cornerRadius = 8;
    self.containerView.layer.borderWidth = 1;
    self.containerView.layer.borderColor = [AppTheme borderColor].CGColor;
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.containerView];

    self.typePill = [SSAccessHitButton buttonWithType:UIButtonTypeSystem];
    self.typePill.titleLabel.font = [AppTheme regularFont:10];
    self.typePill.layer.cornerRadius = 9;
    self.typePill.clipsToBounds = YES;
    self.typePill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.typePill addTarget:self action:@selector(typePillTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.containerView addSubview:self.typePill];

    self.enableSwitch = [[UISwitch alloc] init];
    self.enableSwitch.onTintColor = [AppTheme textHighlightColor];
    self.enableSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.enableSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.containerView addSubview:self.enableSwitch];

    self.addressLabel = [[UILabel alloc] init];
    self.addressLabel.font = [AppTheme monospaceFont:12];
    self.addressLabel.textColor = [AppTheme textColor];
    self.addressLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.addressLabel.adjustsFontSizeToFitWidth = YES;
    self.addressLabel.minimumScaleFactor = 0.8f;
    self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.addressLabel];

    self.symbolLabel = [[UILabel alloc] init];
    self.symbolLabel.font = [AppTheme boldFont:13];
    self.symbolLabel.textColor = [AppTheme textColor];
    self.symbolLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.symbolLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.symbolLabel];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [AppTheme monospaceFont:13];
    self.valueLabel.textColor = [AppTheme valueColor];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.valueLabel];

    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.font = [AppTheme regularFont:10];
    self.metaLabel.textColor = [AppTheme textDisabledColor];
    self.metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.metaLabel];

    self.chevronLabel = [[UILabel alloc] init];
    self.chevronLabel.text = @"›";
    self.chevronLabel.font = [AppTheme regularFont:18];
    self.chevronLabel.textColor = [AppTheme textDisabledColor];
    self.chevronLabel.textAlignment = NSTextAlignmentCenter;
    self.chevronLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.chevronLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [self.containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
        [self.containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
        [self.containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],

        [self.typePill.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:10],
        [self.typePill.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:6],
        [self.typePill.widthAnchor constraintEqualToConstant:52],
        [self.typePill.heightAnchor constraintEqualToConstant:24],

        [self.enableSwitch.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-10],
        [self.enableSwitch.centerYAnchor constraintEqualToAnchor:self.typePill.centerYAnchor],

        [self.addressLabel.leadingAnchor constraintEqualToAnchor:self.typePill.trailingAnchor constant:8],
        [self.addressLabel.centerYAnchor constraintEqualToAnchor:self.typePill.centerYAnchor],
        [self.addressLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.enableSwitch.leadingAnchor constant:-8],

        [self.symbolLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:10],
        [self.symbolLabel.topAnchor constraintEqualToAnchor:self.typePill.bottomAnchor constant:12],
        [self.symbolLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.valueLabel.leadingAnchor constant:-8],

        [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-10],
        [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.symbolLabel.centerYAnchor],
        [self.valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:64],

        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:10],
        [self.metaLabel.topAnchor constraintEqualToAnchor:self.symbolLabel.bottomAnchor constant:4],
        [self.metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronLabel.leadingAnchor constant:-6],
        [self.metaLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.containerView.bottomAnchor constant:-8],

        [self.chevronLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-10],
        [self.chevronLabel.centerYAnchor constraintEqualToAnchor:self.metaLabel.centerYAnchor],
        [self.chevronLabel.widthAnchor constraintEqualToConstant:12]
    ]];
}

- (void)configureWithRecord:(AccessRecord *)record {
    self.currentAddress = record.address;

    self.enableSwitch.on = record.enabled;
    self.enableSwitch.enabled = YES;
    self.enableSwitch.accessibilityLabel = [NSString stringWithFormat:@"启用访问点 0x%llX", record.address];
    self.typePill.enabled = record.enabled;
    self.typePill.accessibilityLabel = [NSString stringWithFormat:@"监视类型 0x%llX", record.address];

    BOOL isWrite = (record.type == SSBreakpointTypeWrite);
    UIColor *accent = isWrite ? [AppTheme writeTypeColor] : [AppTheme textHighlightColor];

    [self.typePill setTitle:(isWrite ? @"写入" : @"访问") forState:UIControlStateNormal];
    [self.typePill setTitleColor:accent forState:UIControlStateNormal];
    self.typePill.backgroundColor = [accent colorWithAlphaComponent:0.18f];

    self.addressLabel.text = [NSString stringWithFormat:@"0x%llX", record.address];

    [self updateLiveValuesWithRecord:record];

    self.containerView.alpha = record.enabled ? 1.0f : 0.55f;
}

- (void)updateLiveValuesWithRecord:(AccessRecord *)record {
    self.valueLabel.text = record.hasValue
        ? [NSString stringWithFormat:@"0x%llX", record.value]
        : @"-";
    self.valueLabel.textColor = record.hasValue ? [AppTheme valueColor] : [AppTheme textDisabledColor];

    NSString *symbolText = record.label;
    if (symbolText.length == 0) {
        if (record.instructionAddr != 0) {
            SSSymbol *symbol = [[SSSymbolicator shared] symbolForAddress:record.instructionAddr];
            symbolText = symbol.shortText;
            if (symbolText.length == 0) {
                symbolText = [NSString stringWithFormat:@"0x%llX", record.instructionAddr];
            }
        } else {
            symbolText = @"尚未触发";
        }
    }
    self.symbolLabel.text = symbolText;

    if (record.hitCount == 0) {
        self.metaLabel.text = @"尚未触发";
    } else {
        NSMutableString *meta = [NSMutableString stringWithFormat:@"命中 %ld", (long)record.hitCount];
        if (record.lastHitAt) {
            [meta appendFormat:@" · %@", [SSAccessTimeFormatter() stringFromDate:record.lastHitAt]];
        }
        if (record.lastThreadId != 0) {
            [meta appendFormat:@" · 线程 0x%X", record.lastThreadId];
        }
        self.metaLabel.text = meta;
    }

    BOOL failed = (record.enabled && !record.armed);
    self.metaLabel.textColor = failed ? [AppTheme errorColor] : [AppTheme textDisabledColor];
    if (failed) {
        self.metaLabel.text = [@"未生效 · " stringByAppendingString:self.metaLabel.text ?: @""];
    }
}

- (void)switchChanged:(UISwitch *)sw {
    [self.delegate accessCellDidChangeEnabled:sw.on forAddress:self.currentAddress];
}

- (void)typePillTapped {
    [self.delegate accessCellDidTapTypeForAddress:self.currentAddress];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.containerView.backgroundColor = highlighted
        ? [AppTheme buttonActiveColor]
        : [UIColor colorWithWhite:0.10f alpha:1.0f];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.delegate = nil;
    self.currentAddress = 0;
    self.enableSwitch.on = NO;
    self.enableSwitch.enabled = YES;
    self.typePill.enabled = YES;
    self.addressLabel.text = nil;
    self.valueLabel.text = nil;
    self.symbolLabel.text = nil;
    self.metaLabel.text = nil;
    self.metaLabel.textColor = [AppTheme textDisabledColor];
    self.containerView.alpha = 1.0f;
}

@end
