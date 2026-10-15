#import "UI/Components/AccessCell.h"
#import "UI/Components/ThemeConfig.h"
#import "Models/AccessRecord.h"

@interface AccessCell ()

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *hitCountLabel;
@property (nonatomic, strong) UISegmentedControl *typeSegment;

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
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    self.containerView = [[UIView alloc] init];
    self.containerView.backgroundColor = [AppTheme childBackgroundColor];
    self.containerView.layer.cornerRadius = 8;
    self.containerView.layer.borderWidth = 1;
    self.containerView.layer.borderColor = [AppTheme borderColor].CGColor;
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.containerView];
    
    self.enableSwitch = [[UISwitch alloc] init];
    self.enableSwitch.onTintColor = [AppTheme textHighlightColor];
    self.enableSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.enableSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.containerView addSubview:self.enableSwitch];
    
    self.addressLabel = [[UILabel alloc] init];
    self.addressLabel.font = [AppTheme monospaceFont:14];
    self.addressLabel.textColor = [AppTheme textColor];
    self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.addressLabel];
    
    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [AppTheme monospaceFont:12];
    self.valueLabel.textColor = [AppTheme valueColor];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.valueLabel];
    
    self.hitCountLabel = [[UILabel alloc] init];
    self.hitCountLabel.font = [AppTheme regularFont:11];
    self.hitCountLabel.textColor = [AppTheme textDisabledColor];
    self.hitCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.hitCountLabel];
    
    self.typeSegment = [[UISegmentedControl alloc] initWithItems:@[@"W", @"R", @"RW"]];
    self.typeSegment.selectedSegmentTintColor = [AppTheme textHighlightColor];
    self.typeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.typeSegment addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.containerView addSubview:self.typeSegment];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [self.containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
        [self.containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
        [self.containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
        
        [self.enableSwitch.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:8],
        [self.enableSwitch.centerYAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:20],
        
        [self.addressLabel.leadingAnchor constraintEqualToAnchor:self.enableSwitch.trailingAnchor constant:8],
        [self.addressLabel.centerYAnchor constraintEqualToAnchor:self.enableSwitch.centerYAnchor],
        
        [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-8],
        [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.enableSwitch.centerYAnchor],
        [self.valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:80],
        
        [self.hitCountLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:8],
        [self.hitCountLabel.topAnchor constraintEqualToAnchor:self.enableSwitch.bottomAnchor constant:8],
        
        [self.typeSegment.leadingAnchor constraintEqualToAnchor:self.hitCountLabel.trailingAnchor constant:8],
        [self.typeSegment.centerYAnchor constraintEqualToAnchor:self.hitCountLabel.centerYAnchor],
        [self.typeSegment.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-8],
        [self.typeSegment.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor constant:-8],
    ]];
}

- (void)switchChanged:(UISwitch *)sw {
    [self.delegate accessCellDidChangeEnabled:sw.on forAddress:self.currentAddress];
}

- (void)segmentChanged:(UISegmentedControl *)segment {
    [self.delegate accessCellDidChangeType:segment.selectedSegmentIndex forAddress:self.currentAddress];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (highlighted) {
        self.containerView.backgroundColor = [AppTheme buttonActiveColor];
    } else {
        self.containerView.backgroundColor = [AppTheme childBackgroundColor];
    }
}

- (void)configureWithRecord:(AccessRecord *)record {
    self.currentAddress = record.address;
    
    self.enableSwitch.on = record.enabled;
    self.enableSwitch.enabled = YES;
    
    NSString *typeIndicator = @"";
    UIColor *addressColor = [AppTheme textColor];
    if (record.type == SSBreakpointTypeWrite) {
        typeIndicator = @"[W] ";
        addressColor = [AppTheme writeTypeColor];
    } else if (record.type == SSBreakpointTypeRead) {
        typeIndicator = @"[R] ";
        addressColor = [AppTheme readTypeColor];
    } else if (record.type == SSBreakpointTypeReadWrite) {
        typeIndicator = @"[RW] ";
        addressColor = [UIColor colorWithRed:0.8f green:0.6f blue:1.0f alpha:1.0f];
    }
    
    self.addressLabel.text = [NSString stringWithFormat:@"%@0x%llX", typeIndicator, record.address];
    self.addressLabel.textColor = addressColor;
    
    if (record.value != 0) {
        self.valueLabel.text = [NSString stringWithFormat:@"0x%llX", record.value];
    } else {
        self.valueLabel.text = @"-";
    }
    
    self.hitCountLabel.text = [NSString stringWithFormat:@"命中: %ld", (long)record.hitCount];
    
    if (record.type == SSBreakpointTypeWrite) {
        self.typeSegment.selectedSegmentIndex = 0;
    } else if (record.type == SSBreakpointTypeRead) {
        self.typeSegment.selectedSegmentIndex = 1;
    } else if (record.type == SSBreakpointTypeReadWrite) {
        self.typeSegment.selectedSegmentIndex = 2;
    }
    
    self.typeSegment.enabled = record.enabled;
    self.containerView.alpha = record.enabled ? 1.0f : 0.5f;
}

@end
