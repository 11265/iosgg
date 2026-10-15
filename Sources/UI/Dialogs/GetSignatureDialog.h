#import <UIKit/UIKit.h>

// 特征码长度输入弹框代理
@protocol SSPatternLengthViewDelegate <NSObject>
- (void)patternLengthView:(id)view 
      didConfirmWithLength:(NSInteger)length 
                  address:(uint64_t)address 
             instruction:(uint32_t)instruction 
             disassembly:(NSString *)disassembly;
@end

// 特征码结果弹框代理
@protocol SSPatternResultViewDelegate <NSObject>
- (void)patternResultViewDidConfirm:(id)view;
- (void)patternResultViewDidCopy:(id)view;
@end

// 特征码长度输入弹框
@interface SSPatternLengthView : UIView

@property (nonatomic, weak) id<SSPatternLengthViewDelegate> delegate;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint32_t instruction;
@property (nonatomic, copy) NSString *disassembly;

- (instancetype)initWithAddress:(uint64_t)address 
                   instruction:(uint32_t)instruction 
                  disassembly:(NSString *)disassembly;
- (void)showInView:(UIView *)view;
- (void)hide;

@end

// 特征码结果弹框
@interface SSPatternResultView : UIView

@property (nonatomic, weak) id<SSPatternResultViewDelegate> delegate;
@property (nonatomic, strong, readonly) UITextView *patternTextView;

- (instancetype)initWithPattern:(NSString *)pattern;
- (void)showInView:(UIView *)view;
- (void)hide;

@end 