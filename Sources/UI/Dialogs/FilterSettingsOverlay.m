#import "UI/Dialogs/FilterSettingsOverlay.h"
#import "UI/Components/ThemeConfig.h"

@implementation PointerFilterSettings
@end

@interface FilterSettingsOverlay () <UITextFieldDelegate>
@end

@implementation FilterSettingsOverlay
{
    UIView *_container;
}

- (UITextField *)buildTextField:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard {
    UITextField *tf = [[UITextField alloc] init];
    tf.placeholder = placeholder;
    tf.textColor = IMGUI_TEXT;
    tf.font = [UIFont systemFontOfSize:13];
    tf.backgroundColor = IMGUI_FRAME_BG;
    tf.layer.cornerRadius = 2;
    tf.keyboardType = keyboard;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.delegate = self;
    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 20)];
    tf.leftView = paddingView;
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    return tf;
}

- (instancetype)initWithFrame:(CGRect)frame current:(PointerFilterSettings *)current {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
        
        _container = [[UIView alloc] init];
        _container.backgroundColor = IMGUI_BG_COLOR;
        _container.layer.cornerRadius = 8;
        _container.layer.borderWidth = 1;
        _container.layer.borderColor = [UIColor darkGrayColor].CGColor;
        _container.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_container];
        
        UILabel *title = [[UILabel alloc] init];
        title.text = @"筛选条件";
        title.textColor = IMGUI_TEXT;
        title.font = [UIFont boldSystemFontOfSize:16];
        title.textAlignment = NSTextAlignmentCenter;
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [_container addSubview:title];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_container addSubview:closeBtn];
        
        _moduleField = [self buildTextField:@"模块名包含" keyboard:UIKeyboardTypeDefault];
        _minLevelField = [self buildTextField:@"最小层级" keyboard:UIKeyboardTypeNumberPad];
        _maxLevelField = [self buildTextField:@"最大层级" keyboard:UIKeyboardTypeNumberPad];
        _maxOffsetField = [self buildTextField:@"最大偏移 (Hex)" keyboard:UIKeyboardTypeASCIICapable];
        _valueEqualsField = [self buildTextField:@"最终值等于 (Hex)" keyboard:UIKeyboardTypeASCIICapable];
        
        [_container addSubview:_moduleField];
        [_container addSubview:_minLevelField];
        [_container addSubview:_maxLevelField];
        [_container addSubview:_maxOffsetField];
        [_container addSubview:_valueEqualsField];
        
        UILabel *validLabel = [[UILabel alloc] init];
        validLabel.text = @"仅显示校验有效";
        validLabel.textColor = IMGUI_TEXT;
        validLabel.font = [UIFont systemFontOfSize:13];
        validLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_container addSubview:validLabel];
        
        _validSwitch = [[UISwitch alloc] init];
        _validSwitch.onTintColor = IMGUI_BUTTON_ACTIVE;
        _validSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [_container addSubview:_validSwitch];
        
        UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [applyBtn setTitle:@"应用" forState:UIControlStateNormal];
        [applyBtn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
        applyBtn.backgroundColor = IMGUI_BUTTON;
        applyBtn.layer.cornerRadius = 2;
        [applyBtn addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];
        applyBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_container addSubview:applyBtn];
        
        UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
        [cancelBtn setTitleColor:IMGUI_TEXT forState:UIControlStateNormal];
        cancelBtn.backgroundColor = [UIColor darkGrayColor];
        cancelBtn.layer.cornerRadius = 2;
        [cancelBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_container addSubview:cancelBtn];
        
        [NSLayoutConstraint activateConstraints:@[
            [_container.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_container.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_container.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.88],
            [_container.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.78],
            
            [title.topAnchor constraintEqualToAnchor:_container.topAnchor constant:10],
            [title.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor],
            [title.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor],
            [title.heightAnchor constraintEqualToConstant:30],
            
            [closeBtn.topAnchor constraintEqualToAnchor:_container.topAnchor constant:5],
            [closeBtn.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-10],
            [closeBtn.widthAnchor constraintEqualToConstant:30],
            [closeBtn.heightAnchor constraintEqualToConstant:30],
            
            [_moduleField.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
            [_moduleField.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            [_moduleField.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            [_moduleField.heightAnchor constraintEqualToConstant:30],
            
            [_minLevelField.topAnchor constraintEqualToAnchor:_moduleField.bottomAnchor constant:10],
            [_minLevelField.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            [_minLevelField.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            [_minLevelField.heightAnchor constraintEqualToConstant:30],
            
            [_maxLevelField.topAnchor constraintEqualToAnchor:_minLevelField.bottomAnchor constant:10],
            [_maxLevelField.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            [_maxLevelField.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            [_maxLevelField.heightAnchor constraintEqualToConstant:30],
            
            [_maxOffsetField.topAnchor constraintEqualToAnchor:_maxLevelField.bottomAnchor constant:10],
            [_maxOffsetField.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            [_maxOffsetField.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            [_maxOffsetField.heightAnchor constraintEqualToConstant:30],
            
            [_valueEqualsField.topAnchor constraintEqualToAnchor:_maxOffsetField.bottomAnchor constant:10],
            [_valueEqualsField.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            [_valueEqualsField.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            [_valueEqualsField.heightAnchor constraintEqualToConstant:30],
            
            [validLabel.topAnchor constraintEqualToAnchor:_valueEqualsField.bottomAnchor constant:12],
            [validLabel.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            
            [_validSwitch.centerYAnchor constraintEqualToAnchor:validLabel.centerYAnchor],
            [_validSwitch.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            
            [applyBtn.topAnchor constraintEqualToAnchor:validLabel.bottomAnchor constant:16],
            [applyBtn.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            [applyBtn.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            [applyBtn.heightAnchor constraintEqualToConstant:34],
            
            [cancelBtn.topAnchor constraintEqualToAnchor:applyBtn.bottomAnchor constant:10],
            [cancelBtn.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:12],
            [cancelBtn.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-12],
            [cancelBtn.heightAnchor constraintEqualToConstant:34]
        ]];
        
        if (current) {
            if (current.moduleKeyword.length > 0) _moduleField.text = current.moduleKeyword;
            if (current.minLevelEnabled) _minLevelField.text = [NSString stringWithFormat:@"%ld", (long)current.minLevel];
            if (current.maxLevelEnabled) _maxLevelField.text = [NSString stringWithFormat:@"%ld", (long)current.maxLevel];
            if (current.maxOffsetEnabled) _maxOffsetField.text = [NSString stringWithFormat:@"%llX", current.maxOffset];
            if (current.valueEqualsEnabled) _valueEqualsField.text = [NSString stringWithFormat:@"%llX", current.valueEquals];
            _validSwitch.on = current.onlyValid;
        }
    }
    return self;
}

- (uint64_t)parseHexOrDec:(NSString *)text {
    NSString *trim = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trim.length == 0) return 0;
    if ([trim hasPrefix:@"0x"] || [trim hasPrefix:@"0X"]) {
        trim = [trim substringFromIndex:2];
        return strtoull([trim UTF8String], NULL, 16);
    }
    return strtoull([trim UTF8String], NULL, 10);
}

- (void)applyTapped {
    PointerFilterSettings *settings = [[PointerFilterSettings alloc] init];
    settings.moduleKeyword = _moduleField.text ?: @"";
    settings.minLevelEnabled = _minLevelField.text.length > 0;
    settings.maxLevelEnabled = _maxLevelField.text.length > 0;
    settings.maxOffsetEnabled = _maxOffsetField.text.length > 0;
    settings.valueEqualsEnabled = _valueEqualsField.text.length > 0;
    settings.minLevel = [_minLevelField.text integerValue];
    settings.maxLevel = [_maxLevelField.text integerValue];
    settings.maxOffset = [self parseHexOrDec:_maxOffsetField.text];
    settings.valueEquals = [self parseHexOrDec:_valueEqualsField.text];
    settings.onlyValid = _validSwitch.isOn;
    if (self.onApply) self.onApply(settings);
    [self closeTapped];
}

- (void)closeTapped {
    if (self.onClose) self.onClose();
    [self removeFromSuperview];
}

@end
