#import "UI/Components/TerminalInputField.h"
#import "UI/Components/ThemeConfig.h"

@interface TerminalInputField ()

@property (nonatomic, strong, readwrite) UILabel *titleLabel;
@property (nonatomic, strong, readwrite) UITextField *textField;

@end

@implementation TerminalInputField

@synthesize value = _value;

+ (instancetype)inputFieldWithTitle:(NSString *)title placeholder:(NSString *)placeholder {
    TerminalInputField *field = [[TerminalInputField alloc] init];
    [field configureWithTitle:title placeholder:placeholder];
    return field;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [AppTheme regularFont:14];
    self.titleLabel.textColor = [AppTheme textColor];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.titleLabel];
    
    self.textField = [[UITextField alloc] init];
    self.textField.font = [AppTheme monospaceFont:14];
    self.textField.textColor = [AppTheme textColor];
    self.textField.backgroundColor = [AppTheme frameBackgroundColor];
    self.textField.layer.cornerRadius = [AppTheme cornerRadius];
    self.textField.layer.borderWidth = 0;
    self.textField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 0)];
    self.textField.leftViewMode = UITextFieldViewModeAlways;
    self.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.textField];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.titleLabel.widthAnchor constraintEqualToConstant:45],
        
        [self.textField.leadingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor constant:5],
        [self.textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.textField.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.textField.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.textField.heightAnchor constraintEqualToConstant:24]
    ]];
}

- (void)configureWithTitle:(NSString *)title placeholder:(NSString *)placeholder {
    self.title = title;
    self.placeholder = placeholder;
}

- (void)setTitle:(NSString *)title {
    _title = title;
    self.titleLabel.text = title;
}

- (void)setPlaceholder:(NSString *)placeholder {
    _placeholder = placeholder;
    self.textField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:placeholder ?: @""
        attributes:@{NSForegroundColorAttributeName: [AppTheme textDisabledColor]}];
}

- (void)setValue:(NSString *)newValue {
    _value = [newValue copy];
    self.textField.text = _value;
}

- (NSString *)value {
    return _value;
}

@end
