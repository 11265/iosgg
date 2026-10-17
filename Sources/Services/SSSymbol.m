#import "Services/SSSymbol.h"

@implementation SSSymbol

- (NSString *)formatted {
    if (self.displayName.length == 0) {
        return nil;
    }
    if (self.functionOffset == 0) {
        return self.displayName;
    }
    return [NSString stringWithFormat:@"%@+0x%llX", self.displayName, self.functionOffset];
}

- (NSString *)moduleText {
    if (self.imageName.length > 0) {
        return [NSString stringWithFormat:@"%@+0x%llX", self.imageName, self.imageOffset];
    }
    return [NSString stringWithFormat:@"0x%llX", self.address];
}

- (NSString *)shortText {
    NSString *formatted = [self formatted];
    if (formatted.length > 0) {
        return formatted;
    }
    return [self moduleText];
}

@end
