#import <Foundation/Foundation.h>
#import "External/capstone/capstone.h"
#import "External/keystone/keystone.h"

@interface DisassembledInstruction : NSObject
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint32_t value;
@property (nonatomic, copy) NSString *mnemonic;
@property (nonatomic, copy) NSString *opStr;
@property (nonatomic, assign) BOOL isBranchLink; // bl（MemoryPage 用它展开调用树）
@property (nonatomic, assign) BOOL isBranch;     // 任意直接分支（b/bl/b.cond/cbz/tbz...）
@property (nonatomic, assign) BOOL isConditionalBranch;
@property (nonatomic, assign) uint64_t targetAddress;

// load / store（供指令解释器使用）
@property (nonatomic, assign) BOOL isMemoryAccess;
@property (nonatomic, assign) BOOL isStore;
@property (nonatomic, assign) BOOL isLoad;
@property (nonatomic, copy) NSString *dataRegister;
@property (nonatomic, copy) NSString *memoryBaseRegister;
@property (nonatomic, copy) NSString *memoryIndexRegister;
@property (nonatomic, assign) int64_t memoryDisplacement;
@end

@interface ARM64Assembler : NSObject

// 汇编单条指令
+ (uint32_t)assembleInstruction:(NSString *)instruction atAddress:(uint64_t)address;

// 反汇编单条指令 (Legacy string format)
+ (NSString *)disassembleInstruction:(uint32_t)instruction atAddress:(uint64_t)address;

// 反汇编单条指令 (Structured format)
+ (DisassembledInstruction *)disassemble:(uint32_t)instruction atAddress:(uint64_t)address;

@end
