#import <Foundation/Foundation.h>
#import <mach/mach.h>

typedef void (^RemoteCallCompletionBlock)(uint64_t returnValue, NSError *error);

@interface RemoteCallEngine : NSObject

+ (instancetype)sharedInstance;

- (BOOL)callFunctionAtAddress:(uint64_t)address
                    parameters:(NSArray<NSNumber *> *)params
                   paramCount:(NSInteger)count
                   completion:(RemoteCallCompletionBlock)completion;

- (uint64_t)callFunctionAtAddress:(uint64_t)address
                        parameters:(NSArray<NSNumber *> *)params
                       paramCount:(NSInteger)count
                             error:(NSError **)error;

- (BOOL)allocateMemoryInTarget:(size_t)size
                       address:(mach_vm_address_t *)address
                         error:(NSError **)error;

- (BOOL)writeMemoryAtAddress:(mach_vm_address_t)address
                     data:(const void *)data
                     size:(size_t)size
                    error:(NSError **)error;

- (BOOL)readMemoryAtAddress:(mach_vm_address_t)address
                    data:(void *)data
                    size:(size_t)size
                   error:(NSError **)error;

- (uint64_t)testMemoryCall:(NSError **)error;

- (uint64_t)testSimpleReturn:(uint64_t)testValue error:(NSError **)error;

@end
