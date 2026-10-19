#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PointerChainResolver : NSObject

+ (uint64_t)resolvePointerChain:(NSArray *)chain 
                      moduleBase:(uint64_t)moduleBase
                           error:(NSError **)error;

+ (NSArray *)parseChainExpression:(NSString *)expression 
                            error:(NSError **)error;

+ (NSString *)formatChainToString:(NSArray *)chain;

+ (uint64_t)getModuleBase:(NSString *)moduleName;

@end

NS_ASSUME_NONNULL_END
