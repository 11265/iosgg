#import <UIKit/UIKit.h>

@protocol SSInstructionEditViewDelegate <NSObject>
- (void)instructionEditView:(id)view didConfirmWithInstruction:(NSString *)instruction address:(uint64_t)address;
@end

@interface SSInstructionEditView : UIView

@property (nonatomic, weak) id<SSInstructionEditViewDelegate> delegate;
@property (nonatomic, assign) uint64_t address;

- (instancetype)initWithAddress:(uint64_t)address currentInstruction:(NSString *)instruction;
- (void)showInView:(UIView *)view;
- (void)hide;

@end 