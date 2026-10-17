#import "UI/Components/SSDisassemblyCell.h"
#import "UI/Components/ThemeConfig.h"

@implementation SSDisassemblyLine
@end

@interface SSDisassemblyCell ()

@property (nonatomic, strong) UILabel *mainLabel;
@property (nonatomic, strong) UILabel *annotationLabel;

@end

@implementation SSDisassemblyCell

+ (NSString *)reuseIdentifier {
    return @"SSDisassemblyCell";
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.mainLabel = [[UILabel alloc] init];
        self.mainLabel.numberOfLines = 1;
        self.mainLabel.adjustsFontSizeToFitWidth = YES;
        self.mainLabel.minimumScaleFactor = 0.7f;
        self.mainLabel.lineBreakMode = NSLineBreakByClipping;
        self.mainLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.mainLabel];

        self.annotationLabel = [[UILabel alloc] init];
        self.annotationLabel.font = [AppTheme monospaceFont:10];
        self.annotationLabel.textColor = [AppTheme textHighlightColor];
        self.annotationLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.annotationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.annotationLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.mainLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],
            [self.mainLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [self.mainLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],

            [self.annotationLabel.topAnchor constraintEqualToAnchor:self.mainLabel.bottomAnchor constant:1],
            [self.annotationLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [self.annotationLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8]
        ]];
    }
    return self;
}

- (void)configureWithLine:(SSDisassemblyLine *)line {
    UIFont *addressFont = [AppTheme monospaceFont:10];
    UIFont *bytesFont = [AppTheme monospaceFont:10];
    UIFont *mnemonicFont = [AppTheme monospaceBoldFont:12];
    UIFont *operandFont = [AppTheme monospaceFont:12];

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];

    NSString *addressText = [NSString stringWithFormat:@"0x%09llX  ", line.address];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:addressText
                                                                 attributes:@{
                                                                     NSFontAttributeName: addressFont,
                                                                     NSForegroundColorAttributeName: [AppTheme textDisabledColor]
                                                                 }]];

    NSString *bytesText = [NSString stringWithFormat:@"%@  ", line.bytesText ?: @""];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:bytesText
                                                                 attributes:@{
                                                                     NSFontAttributeName: bytesFont,
                                                                     NSForegroundColorAttributeName: [UIColor colorWithWhite:0.4f alpha:1.0f]
                                                                 }]];

    UIColor *instructionColor = line.isCurrent ? [AppTheme valueColor] : [AppTheme textColor];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:line.mnemonic ?: @""
                                                                 attributes:@{
                                                                     NSFontAttributeName: mnemonicFont,
                                                                     NSForegroundColorAttributeName: instructionColor
                                                                 }]];
    if (line.operands.length > 0) {
        NSString *operands = [@" " stringByAppendingString:line.operands];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:operands
                                                                     attributes:@{
                                                                         NSFontAttributeName: operandFont,
                                                                         NSForegroundColorAttributeName: instructionColor
                                                                     }]];
    }

    self.mainLabel.attributedText = text;

    self.annotationLabel.text = line.annotation;
    self.annotationLabel.hidden = (line.annotation.length == 0);
    self.accessoryType = (line.isBranch && line.branchTarget != 0)
        ? UITableViewCellAccessoryDisclosureIndicator
        : UITableViewCellAccessoryNone;

    self.contentView.backgroundColor = line.isCurrent
        ? [UIColor colorWithRed:0.26f green:0.59f blue:0.98f alpha:0.16f]
        : [UIColor clearColor];
}

@end
