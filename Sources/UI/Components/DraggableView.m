#import "UI/Components/DraggableView.h"

@implementation DragView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (CGRectGetWidth(frame) <= 0 ||
        CGRectGetHeight(frame) <= 0) {
        frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, 130, 60, 60);
    }
    
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.borderColor = [UIColor redColor].CGColor;
        self.layer.borderWidth = 1.0f;
        self.backgroundColor = [UIColor lightGrayColor];
        
        self.clipsToBounds = YES;
        self.layer.cornerRadius = CGRectGetWidth(self.bounds) / 2;
        self.alpha = 1.0f;
        
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = NO;
        self.exclusiveTouch = YES;
        
        // 添加点击手势
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tapGesture.cancelsTouchesInView = NO;
        tapGesture.delaysTouchesBegan = NO;
        tapGesture.delaysTouchesEnded = NO;
        [self addGestureRecognizer:tapGesture];
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    self.alpha = 0.7;
    
    [self.superview bringSubviewToFront:self];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.superview];
    self.center = point;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    self.alpha = 1.0;
    [self adjustPosition];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    self.alpha = 1.0;
    [self adjustPosition];
}

- (void)adjustPosition
{
    CGRect frame = self.frame;
    CGRect superviewBounds = self.superview.bounds;
    
    // 确保视图不会超出父视图的边界
    if (CGRectGetMinX(frame) < 0) {
        frame.origin.x = 0;
    } else if (CGRectGetMaxX(frame) > superviewBounds.size.width) {
        frame.origin.x = superviewBounds.size.width - CGRectGetWidth(frame);
    }
    
    if (CGRectGetMinY(frame) < 0) {
        frame.origin.y = 0;
    } else if (CGRectGetMaxY(frame) > superviewBounds.size.height) {
        frame.origin.y = superviewBounds.size.height - CGRectGetHeight(frame);
    }
    
    [UIView animateWithDuration:0.3 animations:^{
        self.frame = frame;
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIButton *closeButton = [self.subviews firstObject];
    if ([closeButton isKindOfClass:[UIButton class]]) {
        closeButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 20, 0, 20, 20);
    }
}

// 添加点击手势处理方法
- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if ([self.delegate respondsToSelector:@selector(dragViewDidTap:)]) {
        [self.delegate dragViewDidTap:self];
    }
}

@end
