#import "UI/Pages/Record/RecordPage.h"
#import "Modules/Debugger/SSDebugger.h"

@interface RecordPage (Actions)

- (void)closeButtonTapped;
- (void)accessButtonTapped;
- (void)addSelectedToAccessPageWithType:(SSBreakpointType)type;
- (void)clearButtonTapped;
- (void)addButtonTapped;
- (void)modifyAllButtonTapped;
- (void)modifyAllAddressesWithValue:(NSString *)valueStr;
- (void)selectButtonTapped:(UIButton *)sender;
- (void)modifySelectedButtonTapped;
- (void)modifySelectedAddressesWithValue:(NSString *)valueStr;
- (void)calculateButtonTapped;

@end
