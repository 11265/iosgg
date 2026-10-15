#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AccessRegisterViewController : UIViewController

@property (nonatomic, strong) NSDictionary *registers;
@property (nonatomic, strong) NSArray *callStack;
@property (nonatomic, strong) NSString *accessInfo;
@property (nonatomic, assign) uint64_t instructionAddr;
@property (nonatomic, assign) uint64_t memoryAddress;

/// YES = 显示"继续"按钮，并在页面关闭时自动继续被断住的线程
@property (nonatomic, assign) BOOL showsResumeControls;
@end

NS_ASSUME_NONNULL_END