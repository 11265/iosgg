#import "Models/SSDataTypeUtility.h"

@implementation SSDataTypeUtility

+ (NSString *)stringForType:(SearchDataType)type {
    switch (type) {
        case SearchDataTypeU8:  return @"u8";
        case SearchDataTypeI16: return @"i16";
        case SearchDataTypeI32: return @"i32";
        case SearchDataTypeI64: return @"i64";
        case SearchDataTypeF32: return @"f32";
        case SearchDataTypeF64: return @"f64";
    }
    return @"i32";
}

+ (SearchDataType)typeFromString:(NSString *)string {
    if (string.length == 0) return SearchDataTypeI32;
    if ([string isEqualToString:@"u8"]  || [string isEqualToString:@"i8"])  return SearchDataTypeU8;
    if ([string isEqualToString:@"i16"] || [string isEqualToString:@"u16"]) return SearchDataTypeI16;
    if ([string isEqualToString:@"i32"] || [string isEqualToString:@"u32"]) return SearchDataTypeI32;
    if ([string isEqualToString:@"i64"])                                    return SearchDataTypeI64;
    if ([string isEqualToString:@"f32"])                                    return SearchDataTypeF32;
    if ([string isEqualToString:@"f64"])                                    return SearchDataTypeF64;
    return SearchDataTypeI32;
}

+ (size_t)widthForType:(SearchDataType)type {
    return 获取类型大小(type);   // 唯一权威来源（Scanner C 层）
}

+ (NSString *)hexStringForValue:(uint64_t)value type:(SearchDataType)type {
    switch (type) {
        case SearchDataTypeU8:
            return [NSString stringWithFormat:@"%02llX", (unsigned long long)(value & 0xFF)];
        case SearchDataTypeI16:
            return [NSString stringWithFormat:@"%04llX", (unsigned long long)(value & 0xFFFF)];
        case SearchDataTypeI32:
        case SearchDataTypeF32:
            return [NSString stringWithFormat:@"%08llX", (unsigned long long)(uint32_t)value];
        case SearchDataTypeI64:
        case SearchDataTypeF64:
            return [NSString stringWithFormat:@"%016llX", (unsigned long long)value];
    }
    return @"";
}

+ (NSString *)decimalStringForValue:(uint64_t)value type:(SearchDataType)type {
    switch (type) {
        case SearchDataTypeU8:
            return [NSString stringWithFormat:@"%u", (uint8_t)value];
        case SearchDataTypeI16:
            return [NSString stringWithFormat:@"%d", (int16_t)value];
        case SearchDataTypeI32:
            return [NSString stringWithFormat:@"%d", (int32_t)value];
        case SearchDataTypeI64:
            return [NSString stringWithFormat:@"%lld", (int64_t)value];
        case SearchDataTypeF32: {
            uint32_t bits = (uint32_t)value;
            return [NSString stringWithFormat:@"%f", *(float *)&bits];
        }
        case SearchDataTypeF64:
            return [NSString stringWithFormat:@"%lf", *(double *)&value];
    }
    return @"";
}

+ (uint64_t)rawValueFromInput:(NSString *)input type:(SearchDataType)type {
    if (input.length == 0) return 0;
    BOOL isHex = [input hasPrefix:@"0x"] || [input hasPrefix:@"0X"];

    switch (type) {
        case SearchDataTypeU8: {
            if (isHex) { unsigned int h; [[NSScanner scannerWithString:input] scanHexInt:&h]; return (uint64_t)(uint8_t)h; }
            return (uint64_t)(uint8_t)[input intValue];
        }
        case SearchDataTypeI16: {
            if (isHex) { unsigned int h; [[NSScanner scannerWithString:input] scanHexInt:&h]; return (uint64_t)(int16_t)h; }
            return (uint64_t)(int16_t)[input intValue];
        }
        case SearchDataTypeI32: {
            if (isHex) { unsigned int h; [[NSScanner scannerWithString:input] scanHexInt:&h]; return (uint64_t)(int32_t)h; }
            return (uint64_t)(int32_t)[input intValue];
        }
        case SearchDataTypeI64: {
            if (isHex) { unsigned long long h; [[NSScanner scannerWithString:input] scanHexLongLong:&h]; return h; }
            return (uint64_t)[input longLongValue];
        }
        case SearchDataTypeF32: {
            float f = [input floatValue];
            return (uint64_t)*(uint32_t *)&f;
        }
        case SearchDataTypeF64: {
            double d = [input doubleValue];
            return *(uint64_t *)&d;
        }
    }
    return 0;
}

@end
