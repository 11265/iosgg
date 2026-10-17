#import <Foundation/Foundation.h>
#import "External/capstone/capstone.h"
#import "External/keystone/keystone.h"

@interface DisassembledInstruction : NSObject
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint32_t value;
@property (nonatomic, copy) NSString *mnemonic;
@property (nonatomic, copy) NSString *opStr;
@property (nonatomic, assign) BOOL isBranchLink; // bl
@property (nonatomic, assign) uint64_t targetAddress;
@end

@interface ARM64Assembler : NSObject

// 汇编单条指令
+ (uint32_t)assembleInstruction:(NSString *)instruction atAddress:(uint64_t)address;

// 反汇编单条指令 (Legacy string format)
+ (NSString *)disassembleInstruction:(uint32_t)instruction atAddress:(uint64_t)address;

// 反汇编单条指令 (Structured format)
+ (DisassembledInstruction *)disassemble:(uint32_t)instruction atAddress:(uint64_t)address;

@end
