#import <UIKit/UIKit.h>

@class SSOffsetCalculatorView;
@class SSOffsetResultView;

@protocol SSOffsetCalculatorViewDelegate <NSObject>

- (void)offsetCalculatorView:(SSOffsetCalculatorView *)view didConfirmWithModuleName:(NSString *)moduleName;

@end

@protocol SSOffsetResultViewDelegate <NSObject>

- (void)offsetResultViewDidCopy:(SSOffsetResultView *)view;
- (void)offsetResultViewDidConfirm:(SSOffsetResultView *)view;

@end

@interface SSOffsetCalculatorView : UIView

@property (nonatomic, weak) id<SSOffsetCalculatorViewDelegate> delegate;
@property (nonatomic, assign) uint64_t address;

- (instancetype)initWithAddress:(uint64_t)address;
- (void)showInView:(UIView *)view;

@end

@interface SSOffsetResultView : UIView

@property (nonatomic, weak) id<SSOffsetResultViewDelegate> delegate;
@property (nonatomic, strong, readonly) UITextView *offsetTextView;

- (instancetype)initWithOffset:(NSString *)offset;
- (void)showInView:(UIView *)view;

@end 