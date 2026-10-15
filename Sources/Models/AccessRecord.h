#import <Foundation/Foundation.h>
#import "Services/Debugger/SSDebugger.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const kAccessRecordDidUpdateNotification;

@interface AccessHit : NSObject
@property (nonatomic, assign) uint64_t value;
@property (nonatomic, assign) uint64_t instructionAddr;
@property (nonatomic, assign) uint64_t memoryAddress;
@property (nonatomic, assign) SSBreakpointType type;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) NSInteger hitCount;
@property (nonatomic, strong, nullable) NSDictionary *registers;
@property (nonatomic, strong, nullable) NSArray *callStack;
@end

@interface AccessRecord : NSObject
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) uint64_t value;
@property (nonatomic, assign) uint64_t instructionAddr;
@property (nonatomic, assign) SSBreakpointType type;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) NSInteger hitCount;
@property (nonatomic, strong, nullable) NSDictionary *registers;
@property (nonatomic, strong, nullable) NSArray *callStack;

@property (nonatomic, strong) NSMutableArray<AccessHit *> *history;
@end

NS_ASSUME_NONNULL_END