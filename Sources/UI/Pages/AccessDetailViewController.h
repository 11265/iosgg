#import <UIKit/UIKit.h>
#import "Models/AccessRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface AccessDetailsViewController : UIViewController

@property (nonatomic, strong) AccessRecord *record;

@end

NS_ASSUME_NONNULL_END