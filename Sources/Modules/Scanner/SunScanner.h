#import <Foundation/Foundation.h>
#import <mach/mach.h>

@interface SunScanner : NSObject

+ (instancetype)sharedInstance;

- (void)scanSunObjectsWithManagerBase:(uint64_t)managerBase
                            completion:(void(^)(NSArray *sunObjects, NSError *error))completion;

- (BOOL)validateSunObject:(uint64_t)objectAddress
              managerBase:(uint64_t)managerBase
                   sunType:(int *)sunType;

@end
