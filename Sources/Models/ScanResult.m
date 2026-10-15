#import "ScanResult.h"
#import "Services/LogService.h"
#import <stdio.h>

@implementation ScanResult

- (instancetype)initWithMatchCount:(size_t)count
                     resultFilePath:(nullable NSString *)path
                          dataType:(SearchDataType)type {
    self = [super init];
    if (self) {
        _matchCount = count;
        _resultFilePath = [path copy];
        _dataType = type;
        _addresses = nil;
    }
    return self;
}

+ (instancetype)resultWithCount:(size_t)count path:(nullable const char *)path type:(SearchDataType)type {
    NSString *nsPath = path ? [NSString stringWithUTF8String:path] : nil;
    return [[self alloc] initWithMatchCount:count resultFilePath:nsPath dataType:type];
}

- (BOOL)isEmpty {
    return _matchCount == 0;
}

- (NSArray<NSNumber *> *)loadAddresses {
    if (_addresses) return _addresses;
    if (!_resultFilePath || _matchCount == 0) return @[];
    
    FILE *fp = fopen([_resultFilePath UTF8String], "rb");
    if (!fp) {
        [LoggingService log:@"[ScanResult] 无法打开结果文件: %@", _resultFilePath];
        return @[];
    }
    
    NSMutableArray<NSNumber *> *list = [NSMutableArray arrayWithCapacity:_matchCount];
    AddressValuePair pair;
    while (fread(&pair, sizeof(AddressValuePair), 1, fp) == 1) {
        [list addObject:@(pair.address)];
    }
    fclose(fp);
    
    _addresses = [list copy];
    return _addresses;
}

@end
