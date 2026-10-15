#import <UIKit/UIKit.h>
#import "Services/Scanner/Scanner.h"

NS_ASSUME_NONNULL_BEGIN

@class SSBaseAddressPopViewController;

@interface RecordPage : UIViewController
@property (nonatomic, strong) NSMutableArray *savedAddresses;
@property (nonatomic, assign) BOOL isSelectionMode;
- (void)addAddressesToRecord:(NSArray *)addresses;
@end

NS_ASSUME_NONNULL_END