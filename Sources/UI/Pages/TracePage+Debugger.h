#import "UI/Pages/TracePage.h"

@interface SSTrackPopViewController (Debugger)

- (void)startDebugging;
- (void)stopDebugging;
- (void)addMemoryWatchpoint:(uint64_t)address size:(size_t)size type:(SSBreakpointType)type;
- (void)removeAllWatchpoints;
- (void)watchButtonTapped;
- (void)clearButtonTapped;
- (void)startButtonTapped;
- (void)stopButtonTapped;
- (void)updateButtonStates;

@end
