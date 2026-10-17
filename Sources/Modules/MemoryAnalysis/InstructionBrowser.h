#import <Foundation/Foundation.h>
#import <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

@interface InstructionBrowser : NSObject

@property (nonatomic, assign) mach_port_t task;
@property (nonatomic, assign) BOOL isLoading;

- (instancetype)init;
- (BOOL)attachToSelf;
- (uint64_t)readMemoryAtAddress:(uint64_t)address size:(size_t)size error:(NSError **)error;
- (NSString *)disassembleInstruction:(uint32_t)instruction atAddress:(uint64_t)address;

@end

NS_ASSUME_NONNULL_END 