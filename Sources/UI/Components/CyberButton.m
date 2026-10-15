#import "UI/Components/CyberButton.h"
#import "UI/Components/ThemeConfig.h"

@interface CyberButton ()

@property (nonatomic, strong) UIColor *normalBackgroundColor;
@property (nonatomic, strong) UIColor *highlightBackgroundColor;
@property (nonatomic, assign) BOOL isLoading;

@end

@implementation CyberButton

+ (instancetype)buttonWithTitle:(NSString *)title {
    CyberButton *button = [[CyberButton alloc] init];
    [button configureWithTitle:title style:CyberButtonStyleDefault];
    return button;
}

+ (instancetype)buttonWithTitle:(NSString *)title style:(CyberButtonStyle)style {
    CyberButton *button = [[CyberButton alloc] init];
    [button configureWithTitle:title style:style];
    return button;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupDefaults];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self setupDefaults];
    }
    return self;
}

- (void)setupDefaults {
    self.layer.cornerRadius = [AppTheme cornerRadius];
    self.titleLabel.font = [AppTheme regularFont:13];
    [self setTitleColor:[AppTheme textColor] forState:UIControlStateNormal];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.style = CyberButtonStyleDefault;
}

- (void)configureWithTitle:(NSString *)title style:(CyberButtonStyle)style {
    [self setTitle:title forState:UIControlStateNormal];
    self.style = style;
    [self updateColors];
}

- (void)setStyle:(CyberButtonStyle)style {
    _style = style;
    [self updateColors];
}

- (void)updateColors {
    switch (_style) {
        case CyberButtonStylePrimary:
            self.normalBackgroundColor = [AppTheme buttonHoverColor];
            self.highlightBackgroundColor = [AppTheme buttonActiveColor];
            break;
        case CyberButtonStyleDanger:
            self.normalBackgroundColor = [UIColor colorWithRed:0.8f green:0.2f blue:0.2f alpha:0.6f];
            self.highlightBackgroundColor = [UIColor colorWithRed:0.9f green:0.3f blue:0.3f alpha:1.0f];
            break;
        case CyberButtonStyleSuccess:
            self.normalBackgroundColor = [UIColor colorWithRed:0.2f green:0.6f blue:0.3f alpha:0.6f];
            self.highlightBackgroundColor = [UIColor colorWithRed:0.3f green:0.7f blue:0.4f alpha:1.0f];
            break;
        default:
            self.normalBackgroundColor = [AppTheme buttonColor];
            self.highlightBackgroundColor = [AppTheme buttonActiveColor];
            break;
    }
    self.backgroundColor = self.normalBackgroundColor;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (highlighted) {
        self.backgroundColor = self.highlightBackgroundColor;
    } else {
        self.backgroundColor = self.normalBackgroundColor;
    }
}

- (void)setLoading:(BOOL)loading {
    if (_isLoading == loading) return;
    _isLoading = loading;
    
    self.enabled = !loading;
    if (loading) {
        UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        indicator.tag = 1001;
        [indicator startAnimating];
        self.imageView.hidden = YES;
        [self addSubview:indicator];
        indicator.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    } else {
        UIView *indicator = [self viewWithTag:1001];
        [indicator removeFromSuperview];
        self.imageView.hidden = NO;
    }
}

@end
