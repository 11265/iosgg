#import <Foundation/Foundation.h>
#import "Services/Debugger/SSDebugger.h"

NS_ASSUME_NONNULL_BEGIN

@class AccessRecord;

extern NSNotificationName const AccessViewModelDidUpdateNotification;
extern NSNotificationName const AccessViewModelDebugStateChangedNotification;

@interface AccessViewModel : NSObject

@property (nonatomic, readonly) NSArray<AccessRecord *> *records;
@property (nonatomic, readonly) BOOL isDebugging;
@property (nonatomic, readonly) NSUInteger watchpointCount;

- (void)addWatchpoint:(uint64_t)address type:(SSBreakpointType)type;
- (void)removeWatchpointAtIndex:(NSUInteger)index;
- (void)removeAllWatchpoints;

- (void)setEnabled:(BOOL)enabled forAddress:(uint64_t)address;
- (void)setType:(SSBreakpointType)type forAddress:(uint64_t)address;

- (void)startDebugging;
- (void)stopDebugging;
- (void)toggleDebugging;

- (AccessRecord * _Nullable)recordAtIndex:(NSUInteger)index;
- (void)syncWithDebugger;

@end

NS_ASSUME_NONNULL_END
