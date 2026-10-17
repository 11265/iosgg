#import "Modules/Scanner/ScannerState.h"
#import <pthread.h>

@implementation ScannerState

- (pthread_mutex_t *)mutexPtr {
    return &_mutex;
}

- (atomic_size_t *)resultCountPtr {
    return &_resultCount;
}

- (atomic_bool *)scanningPtr {
    return &_scanning;
}

- (atomic_bool *)cancelPtr {
    return &_cancelRequested;
}

- (atomic_size_t *)scanBytesTotalPtr {
    return &_scanBytesTotal;
}

- (atomic_size_t *)scanBytesDonePtr {
    return &_scanBytesDone;
}

+ (instancetype)shared {
    static ScannerState *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ScannerState alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _memoryRangeStart = 0x100000000;  // 4GB
        _memoryRangeEnd   = 0x200000000;  // 8GB
        _scanId = NULL;
        _dumpFilePath = NULL;
        _compressedData = NULL;
        _compressedSize = 0;
        _scanner = NULL;
        _currentSearchMode = 未搜索;
        _memory = NULL;
        _memoryCount = 0;
        _memoryCapacity = 0;
        _mutex = (pthread_mutex_t)PTHREAD_MUTEX_INITIALIZER;
        _resultCount = 0;
        _searchResults = NULL;
        _resultTruncated = NO;
        _scanning = false;
        _cancelRequested = false;
        _scanBytesTotal = 0;
        _scanBytesDone = 0;
        _callback = NULL;
        _currentDataType = SearchDataTypeI32;
    }
    return self;
}

@end
