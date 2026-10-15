#import "Models/AccessRecord.h"

NSNotificationName const kAccessRecordDidUpdateNotification = @"kAccessRecordDidUpdateNotification";

@implementation AccessHit
@end

@implementation AccessRecord
- (instancetype)init {
    if (self = [super init]) {
        _enabled = YES;
        _history = [NSMutableArray array];
    }
    return self;
}
@end