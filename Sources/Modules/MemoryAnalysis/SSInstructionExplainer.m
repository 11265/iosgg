#import "Modules/MemoryAnalysis/SSInstructionExplainer.h"

static uint64_t SSRegisterValue(NSString *name, NSDictionary<NSString *, NSNumber *> *registers) {
    if (name.length == 0 || registers == nil) {
        return 0;
    }
    if ([name isEqualToString:@"xzr"] || [name isEqualToString:@"wzr"]) {
        return 0;
    }
    if ([name isEqualToString:@"wsp"]) {
        return registers[@"sp"].unsignedLongLongValue & 0xFFFFFFFFULL;
    }

    NSNumber *number = registers[name];
    if (!number && [name hasPrefix:@"w"]) {
        // w1 的值在 x1 里，取低 32 位
        number = registers[[@"x" stringByAppendingString:[name substringFromIndex:1]]];
    }
    if (!number && [name isEqualToString:@"fp"]) {
        number = registers[@"x29"];
    }

    uint64_t value = number.unsignedLongLongValue;
    if ([name hasPrefix:@"w"]) {
        value &= 0xFFFFFFFFULL;
    }
    return value;
}

static NSString *SSFormatRegisterValue(NSString *name, uint64_t value) {
    if ([name hasPrefix:@"w"]) {
        return [NSString stringWithFormat:@"0x%08llX", (unsigned long long)value];
    }
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
}

static NSString *SSFormatDisplacement(int64_t displacement) {
    if (displacement == 0) {
        return @"";
    }
    if (displacement > 0) {
        return [NSString stringWithFormat:@"+0x%llX", (unsigned long long)displacement];
    }
    return [NSString stringWithFormat:@"-0x%llX", (unsigned long long)(-displacement)];
}

@implementation SSInstructionExplanation
@end

@implementation SSInstructionExplainer

+ (SSInstructionExplanation *)explainInstruction:(DisassembledInstruction *)instruction
                                             far:(uint64_t)far
                                       registers:(NSDictionary<NSString *, NSNumber *> *)registers
                                           width:(uint8_t)width {
    (void)width;

    if (!instruction.isMemoryAccess) {
        return nil;
    }

    NSMutableString *expression = [NSMutableString string];
    uint64_t address = 0;

    if (instruction.memoryBaseRegister.length > 0) {
        [expression appendString:instruction.memoryBaseRegister];
        address += SSRegisterValue(instruction.memoryBaseRegister, registers);
    }
    if (instruction.memoryIndexRegister.length > 0) {
        if (expression.length > 0) {
            [expression appendString:@" + "];
        }
        [expression appendString:instruction.memoryIndexRegister];
        address += SSRegisterValue(instruction.memoryIndexRegister, registers);
    }
    address += (uint64_t)instruction.memoryDisplacement;
    if (expression.length == 0) {
        [expression appendString:@"?"];
    }
    [expression appendString:SSFormatDisplacement(instruction.memoryDisplacement)];

    SSInstructionExplanation *explanation = [[SSInstructionExplanation alloc] init];

    if (instruction.isStore) {
        uint64_t value = SSRegisterValue(instruction.dataRegister, registers);
        NSString *dataRegister = instruction.dataRegister.length > 0 ? instruction.dataRegister : @"?";
        explanation.summary = [NSString stringWithFormat:@"写入 0x%llX（%@），源 %@ = %@",
                               (unsigned long long)address,
                               expression,
                               dataRegister,
                               SSFormatRegisterValue(dataRegister, value)];
        explanation.isWrite = YES;
    } else {
        NSString *dataRegister = instruction.dataRegister.length > 0 ? instruction.dataRegister : @"?";
        explanation.summary = [NSString stringWithFormat:@"读取 0x%llX（%@）→ %@",
                               (unsigned long long)address,
                               expression,
                               dataRegister];
        explanation.isWrite = NO;
    }

    if (far != 0 && address == far) {
        explanation.summary = [explanation.summary stringByAppendingString:@"  ← 访问地址"];
    }

    return explanation;
}

@end
