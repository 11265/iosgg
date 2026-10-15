#import "UI/Components/MemoryCell.h"
#import "UI/Components/ThemeConfig.h"

@implementation MemoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        self.addressLabel = [[UILabel alloc] init];
        self.addressLabel.font = [UIFont fontWithName:@"Menlo" size:13];
        self.addressLabel.textColor = IMGUI_TEXT_DISABLED;
        self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.addressLabel];
        
        self.expandButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.expandButton setTitle:@"▶" forState:UIControlStateNormal];
        [self.expandButton setTitleColor:IMGUI_CHECKMARK forState:UIControlStateNormal];
        self.expandButton.titleLabel.font = [UIFont systemFontOfSize:10];
        self.expandButton.hidden = YES;
        self.expandButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.expandButton];
        [self.expandButton addTarget:self action:@selector(expandButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        
        self.valueLabel = [[UILabel alloc] init];
        self.valueLabel.font = [UIFont fontWithName:@"Menlo" size:13];
        self.valueLabel.textColor = IMGUI_TEXT;
        self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.valueLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.addressLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [self.addressLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.addressLabel.widthAnchor constraintEqualToConstant:90],
            
            [self.expandButton.leadingAnchor constraintEqualToAnchor:self.addressLabel.trailingAnchor constant:2],
            [self.expandButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.expandButton.widthAnchor constraintEqualToConstant:20],
            [self.expandButton.heightAnchor constraintEqualToConstant:20],
            
            [self.valueLabel.leadingAnchor constraintEqualToAnchor:self.expandButton.trailingAnchor constant:2],
            [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]
        ]];
    }
    return self;
}

- (void)expandButtonTapped {
    if (self.expandBlock) {
        self.expandBlock();
    }
}

@end
