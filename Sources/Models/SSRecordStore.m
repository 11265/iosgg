#import "Models/SSRecordStore.h"

NSNotificationName const kSSRecordStoreDidChangeNotification = @"kSSRecordStoreDidChangeNotification";

@interface SSRecordStore ()
@property (nonatomic, strong, readwrite) NSMutableArray<SSMemoryRecord *> *mutableRecords;
@end

@implementation SSRecordStore

+ (instancetype)sharedStore {
    static SSRecordStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSRecordStore alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _mutableRecords = [NSMutableArray array];
    }
    return self;
}

- (NSArray<SSMemoryRecord *> *)records {
    return [self.mutableRecords copy];
}

- (NSUInteger)count {
    return self.mutableRecords.count;
}

/// 判断新记录是否与已有记录重复：指针链按表达式，普通按地址
- (BOOL)isDuplicate:(SSMemoryRecord *)candidate {
    for (SSMemoryRecord *existing in self.mutableRecords) {
        if (candidate.isPointerChain || existing.isPointerChain) {
            if (candidate.isPointerChain && existing.isPointerChain &&
                [candidate.chainExpression isEqualToString:existing.chainExpression]) {
                return YES;
            }
        } else if (existing.address == candidate.address) {
            return YES;
        }
    }
    return NO;
}

- (void)addRecords:(NSArray<SSMemoryRecord *> *)records {
    if (records.count == 0) return;

    NSUInteger added = 0;
    for (SSMemoryRecord *record in records) {
        if ([self isDuplicate:record]) continue;
        [self.mutableRecords addObject:record];
        added++;
    }

    if (added > 0) {
        [self notifyChange];
    }
}

- (void)removeRecordsAtIndexes:(NSIndexSet *)indexes {
    if (indexes.count == 0) return;
    [self.mutableRecords removeObjectsAtIndexes:indexes];
    [self notifyChange];
}

- (void)removeAll {
    if (self.mutableRecords.count == 0) return;
    [self.mutableRecords removeAllObjects];
    [self notifyChange];
}

- (SSMemoryRecord *)recordAtIndex:(NSUInteger)index {
    if (index >= self.mutableRecords.count) return nil;
    return self.mutableRecords[index];
}

- (SSMemoryRecord *)recordForAddress:(uint64_t)address {
    for (SSMemoryRecord *record in self.mutableRecords) {
        if (!record.isPointerChain && record.address == address) return record;
    }
    return nil;
}

- (void)notifyChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSSRecordStoreDidChangeNotification
                                                            object:self];
    });
}

@end
