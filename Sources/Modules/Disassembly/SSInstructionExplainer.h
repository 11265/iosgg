#import <Foundation/Foundation.h>
#import "Modules/Disassembly/ARM64Assembler.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSInstructionExplanation : NSObject

/// 一句话解释，例如：
///   "写入 0x103A2B4C8（x0+0x18），源 w1 = 0x7F"
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, assign) BOOL isWrite;

@end

@interface SSInstructionExplainer : NSObject

+ (nullable SSInstructionExplanation *)explainInstruction:(DisassembledInstruction *)instruction
                                                      far:(uint64_t)far
                                                registers:(nullable NSDictionary<NSString *, NSNumber *> *)registers
                                                    width:(uint8_t)width;

@end

NS_ASSUME_NONNULL_END
