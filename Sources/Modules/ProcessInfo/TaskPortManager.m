#import "Modules/ProcessInfo/TaskPortManager.h"
#import "Services/LogService.h"

@implementation TaskPortManager {
    mach_port_t _taskPort;
}

+ (instancetype)shared {
    static TaskPortManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _taskPort = mach_task_self();
        if (_taskPort == MACH_PORT_NULL) {
            [LoggingService log:@"初始化task port失败"];
        }
    }
    return self;
}

- (mach_port_t)taskPort {
    return _taskPort;
}

@end
