#import "Modules/MemoryAnalysis/ARM64Assembler.h"
#import "Services/LogService.h"
#import "External/capstone/capstone.h"
#import "External/capstone/arm64.h"
#import "External/keystone/keystone.h"

@implementation DisassembledInstruction
@end

@implementation ARM64Assembler

static csh _capstoneHandle = 0;
static dispatch_once_t _capstoneOnceToken;
/// Capstone 的 handle 不支持并发调用：MemoryPage 的后台反汇编与检查器的主线程反汇编会撞上
static NSObject *_capstoneLock = nil;

static NSString *SSRegisterName(unsigned int reg) {
    if (reg == ARM64_REG_INVALID || _capstoneHandle == 0) {
        return nil;
    }
    const char *name = cs_reg_name(_capstoneHandle, reg);
    return name ? [NSString stringWithUTF8String:name] : nil;
}

+ (void)initializeCapstone {
    dispatch_once(&_capstoneOnceToken, ^{
        _capstoneLock = [[NSObject alloc] init];
        cs_err err = cs_open(CS_ARCH_AARCH64, CS_MODE_LITTLE_ENDIAN, &_capstoneHandle);
        if (err != CS_ERR_OK) {
            [LoggingService log:@"Failed to initialize Capstone: %d", err];
            _capstoneHandle = 0;
        } else {
            cs_option(_capstoneHandle, CS_OPT_DETAIL, CS_OPT_ON);
            [LoggingService log:@"Capstone initialized successfully"];
        }
    });
}

+ (uint32_t)parseRegister:(NSString *)regStr {
    if ([regStr isEqualToString:@"sp"]) return 31;
    if ([regStr hasPrefix:@"x"] || [regStr hasPrefix:@"w"]) {
        return [[regStr substringFromIndex:1] intValue];
    }
    return 0;
}

+ (int64_t)parseImmediate:(NSString *)immStr {
    if ([immStr hasPrefix:@"#"]) {
        immStr = [immStr substringFromIndex:1];
    }
    if ([immStr hasPrefix:@"0x"]) {
        uint64_t value;
        NSScanner *scanner = [NSScanner scannerWithString:immStr];
        [scanner scanHexLongLong:&value];
        return value;
    }
    return [immStr longLongValue];
}

// 汇编初始化
+ (uint32_t)assembleInstruction:(NSString *)instruction atAddress:(uint64_t)address {
    ks_engine *ks;
    ks_err err;
    size_t count;
    unsigned char *encode;
    size_t size;
    uint32_t result = 0;
    
    // 初始化 Keystone
    err = ks_open(KS_ARCH_ARM64, KS_MODE_LITTLE_ENDIAN, &ks);
    if (err != KS_ERR_OK) {
        [LoggingService log:@"ERROR: 无法初始化 Keystone: %s", ks_strerror(err)];
        return 0;
    }
    
    // 进行汇编
    if (ks_asm(ks, [instruction UTF8String], address, &encode, &size, &count) != KS_ERR_OK) {
        [LoggingService log:@"ERROR: 汇编失败: %s", ks_strerror(ks_errno(ks))];
        ks_close(ks);
        return 0;
    }
    
    // 获取汇编结果
    if (size >= 4) {
        result = *(uint32_t*)encode;
        [LoggingService log:@"汇编成功: %@ -> 0x%08x", instruction, result];
    }
    
    // 释放资源
    ks_free(encode);
    ks_close(ks);
    
    return result;
}

// 反汇编单条指令 (Legacy string format)
+ (NSString *)disassembleInstruction:(uint32_t)instruction atAddress:(uint64_t)address {
    DisassembledInstruction *info = [self disassemble:instruction atAddress:address];
    if ([info.mnemonic isEqualToString:@".word"]) {
        return [NSString stringWithFormat:@".word 0x%08x", instruction];
    }
    return [NSString stringWithFormat:@"%@ %@", info.mnemonic, info.opStr];
}

// 反汇编单条指令 (Structured format)
+ (DisassembledInstruction *)disassemble:(uint32_t)instruction atAddress:(uint64_t)address {
    [self initializeCapstone];
    
    DisassembledInstruction *info = [[DisassembledInstruction alloc] init];
    info.address = address;
    info.value = instruction;
    info.isBranchLink = NO;
    info.isBranch = NO;
    info.isConditionalBranch = NO;
    info.targetAddress = 0;
    info.isMemoryAccess = NO;
    info.isStore = NO;
    info.isLoad = NO;
    info.memoryDisplacement = 0;
    
    if (_capstoneHandle == 0) {
        info.mnemonic = @".word";
        info.opStr = [NSString stringWithFormat:@"0x%08x", instruction];
        return info;
    }
    
    uint8_t bytes[4];
    bytes[0] = instruction & 0xFF;
    bytes[1] = (instruction >> 8) & 0xFF;
    bytes[2] = (instruction >> 16) & 0xFF;
    bytes[3] = (instruction >> 24) & 0xFF;
    
    cs_insn *insn;
    size_t count = 0;
    @synchronized (_capstoneLock) {
        count = cs_disasm(_capstoneHandle, bytes, sizeof(bytes), address, 1, &insn);
    }
    
    if (count > 0) {
        info.mnemonic = [NSString stringWithUTF8String:insn[0].mnemonic];
        info.opStr = [NSString stringWithUTF8String:insn[0].op_str];
        
        if (insn[0].detail) {
            cs_arm64 *detail = &insn[0].detail->aarch64;
            switch (insn[0].id) {
                case ARM64_INS_B:
                case ARM64_INS_BL:
                case ARM64_INS_CBZ:
                case ARM64_INS_CBNZ:
                case ARM64_INS_TBZ:
                case ARM64_INS_TBNZ: {
                    info.isBranch = YES;
                    if (insn[0].id == ARM64_INS_B && detail->cc != ARM64_CC_AL) {
                        info.isConditionalBranch = YES;
                    }
                    if (detail->op_count > 0 && detail->operands[0].type == ARM64_OP_IMM) {
                        info.targetAddress = (uint64_t)detail->operands[0].imm;
                    }
                    break;
                }
                default:
                    break;
            }
            if (insn[0].id == ARM64_INS_BL) {
                info.isBranchLink = YES;
            }

            const char *mnemonic = insn[0].mnemonic;
            BOOL looksLikeStore = (mnemonic[0] == 's' && mnemonic[1] == 't');
            BOOL looksLikeLoad = (mnemonic[0] == 'l' && mnemonic[1] == 'd');
            if (looksLikeStore || looksLikeLoad) {
                for (int i = 0; i < detail->op_count; i++) {
                    if (detail->operands[i].type == ARM64_OP_MEM) {
                        info.isMemoryAccess = YES;
                        info.isStore = looksLikeStore;
                        info.isLoad = looksLikeLoad;
                        info.memoryBaseRegister = SSRegisterName(detail->operands[i].mem.base);
                        info.memoryIndexRegister = SSRegisterName(detail->operands[i].mem.index);
                        info.memoryDisplacement = detail->operands[i].mem.disp;
                        break;
                    }
                }
                if (info.isMemoryAccess && detail->op_count > 0 &&
                    detail->operands[0].type == ARM64_OP_REG) {
                    info.dataRegister = SSRegisterName(detail->operands[0].reg);
                }
            }
        }
        
        cs_free(insn, count);
    } else {
        info.mnemonic = @".word";
        info.opStr = [NSString stringWithFormat:@"0x%08x", instruction];
    }
    
    return info;
}

@end
