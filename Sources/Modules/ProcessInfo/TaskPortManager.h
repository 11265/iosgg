#import <Foundation/Foundation.h>
#import <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

@interface TaskPortManager : NSObject

@property (nonatomic, assign, readonly) mach_port_t taskPort;

+ (instancetype)shared;

@end

NS_ASSUME_NONNULL_END
