#import "Models/SSMemoryRecord.h"
#import "Models/SSDataTypeUtility.h"

@implementation SSMemoryRecord

- (instancetype)init {
    if (self = [super init]) {
        _type = SearchDataTypeI32;
    }
    return self;
}

- (NSString *)typeString {
    return [SSDataTypeUtility stringForType:self.type];
}

- (NSString *)addressString {
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)self.address];
}

- (NSString *)hexValueString {
    return [SSDataTypeUtility hexStringForValue:self.lastValue type:self.type];
}

- (NSString *)decimalValueString {
    return [SSDataTypeUtility decimalStringForValue:self.lastValue type:self.type];
}

- (NSString *)displayAddressText {
    if (self.isPointerChain) {
        return self.chainExpression.length > 0 ? self.chainExpression : @"指针链";
    }
    return self.addressString;
}

@end
