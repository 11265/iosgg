#import <Foundation/Foundation.h>

@class DisassembledInstruction;

NS_ASSUME_NONNULL_BEGIN

/// Model representing a single row in the memory browser's assembly view.
@interface DisplayItem : NSObject
@property (nonatomic, strong, nullable) DisassembledInstruction *instruction;
@property (nonatomic, assign) int depth;
@property (nonatomic, assign) BOOL isExpanded;
@end

NS_ASSUME_NONNULL_END
