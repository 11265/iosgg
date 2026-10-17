#import "Services/SSSymbolicator.h"

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

#import "Services/LogService.h"

NSNotificationName const SSSymbolicatorObjCMethodsDidBecomeReadyNotification =
    @"SSSymbolicatorObjCMethodsDidBecomeReadyNotification";

NSNotificationName const SSSymbolicatorDidUpdateSymbolsNotification =
    @"SSSymbolicatorDidUpdateSymbolsNotification";

#ifndef LC_FUNCTION_STARTS
#define LC_FUNCTION_STARTS 0x26
#endif

#pragma mark - Helpers

/// arm64e 返回地址高位带 PAC；统一掩到 48 位用户地址。
static inline uint64_t SSStripPAC(uint64_t pointer) {
    return pointer & 0x0000FFFFFFFFFFFFULL;
}

typedef struct {
    uint64_t addr;
    uint32_t strx;
} SSSymEntry;

typedef struct {
    uint64_t imp;
    const char *className;
    const char *selectorName;
    uint8_t isClassMethod;
} SSObjCMethodEntry;

static int SSObjCMethodEntryCompare(const void *a, const void *b) {
    const SSObjCMethodEntry *lhs = (const SSObjCMethodEntry *)a;
    const SSObjCMethodEntry *rhs = (const SSObjCMethodEntry *)b;
    if (lhs->imp < rhs->imp) return -1;
    if (lhs->imp > rhs->imp) return 1;
    return 0;
}

static int SSSymEntryCompare(const void *a, const void *b) {
    const SSSymEntry *lhs = (const SSSymEntry *)a;
    const SSSymEntry *rhs = (const SSSymEntry *)b;
    if (lhs->addr < rhs->addr) return -1;
    if (lhs->addr > rhs->addr) return 1;
    return 0;
}

/// 第一个 > value 的下标
static size_t SSUpperBoundU64(const uint64_t *arr, size_t count, uint64_t value) {
    size_t lo = 0, hi = count;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (arr[mid] <= value) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

static size_t SSSymUpperBound(const SSSymEntry *arr, size_t count, uint64_t value) {
    size_t lo = 0, hi = count;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (arr[mid].addr <= value) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

/// ObjC 名字已经是可读的；Swift/C++ 做一次 demangle，失败就保留原名。
static NSString *SSDemangleName(NSString *rawName, SSSymbolKind *outKind) {
    if (rawName.length == 0) {
        return nil;
    }

    SSSymbolKind kind = SSSymbolKindFunction;
    const char *name = rawName.UTF8String;
    if (!name) {
        *outKind = kind;
        return rawName;
    }

    if (strncmp(name, "-[", 2) == 0 || strncmp(name, "+[", 2) == 0) {
        *outKind = SSSymbolKindObjC;
        return rawName;
    }

    if (strncmp(name, "$s", 2) == 0 || strncmp(name, "_$s", 3) == 0) {
        kind = SSSymbolKindSwift;
        const char *mangled = (name[0] == '_') ? name + 1 : name;

        typedef char *(*SwiftDemangleFn)(const char *, size_t, char *, size_t *, uint32_t);
        static SwiftDemangleFn demangleFn = NULL;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            demangleFn = (SwiftDemangleFn)dlsym(RTLD_DEFAULT, "swift_demangle");
        });

        if (demangleFn) {
            char *out = demangleFn(mangled, strlen(mangled), NULL, NULL, 0);
            if (out) {
                NSString *result = [NSString stringWithUTF8String:out];
                free(out);
                if (result.length > 0) {
                    *outKind = kind;
                    return result;
                }
            }
        }
        *outKind = kind;
        return rawName;
    }

    // Mach-O 里 C++ 符号是 "__Z..."（一个 Mach-O 前缀 + "_Z"），__cxa_demangle 要 "_Z..."
    if (strncmp(name, "__Z", 3) == 0 || strncmp(name, "_Z", 2) == 0) {
        const char *mangled = (strncmp(name, "__Z", 3) == 0) ? name + 1 : name;

        typedef char *(*CxaDemangleFn)(const char *, char *, size_t *, int *);
        static CxaDemangleFn demangleFn = NULL;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            demangleFn = (CxaDemangleFn)dlsym(RTLD_DEFAULT, "__cxa_demangle");
        });

        if (demangleFn) {
            int status = -1;
            char *out = demangleFn(mangled, NULL, NULL, &status);
            if (status == 0 && out) {
                NSString *result = [NSString stringWithUTF8String:out];
                free(out);
                if (result.length > 0) {
                    *outKind = kind;
                    return result;
                }
            }
        }
        *outKind = kind;
        return rawName;
    }

    *outKind = kind;
    return rawName;
}

#pragma mark - Per-image symbol table

@interface SSImageSymbols : NSObject {
@public
    uint64_t _slide;
    uint64_t _base;
    uint64_t _end;
    uint64_t _textBase;
    uint64_t _headerAddress;
    uint64_t _linkeditVmaddr;
    uint64_t _linkeditFileoff;
    uint64_t _linkeditVmsize;
    BOOL _hasLinkedit;

    const char *_strtab;
    size_t _strsize;

    SSSymEntry *_entries;
    size_t _entryCount;

    uint64_t *_functionStarts;
    size_t _functionCount;

    BOOL _built;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;

- (void)buildIfNeeded;
- (BOOL)hasSymbols;

@end

@implementation SSImageSymbols

- (void)dealloc {
    if (_entries) {
        free(_entries);
        _entries = NULL;
    }
    if (_functionStarts) {
        free(_functionStarts);
        _functionStarts = NULL;
    }
}

- (BOOL)hasSymbols {
    return _entryCount > 0 || _functionCount > 0;
}

- (void)buildIfNeeded {
    @synchronized (self) {
        if (_built) {
            return;
        }
        _built = YES;

        const struct mach_header_64 *header =
            (const struct mach_header_64 *)(uintptr_t)_headerAddress;
        if (!header || header->magic != MH_MAGIC_64) {
            return;
        }

        const struct symtab_command *symtabCmd = NULL;
        const struct linkedit_data_command *functionStartsCmd = NULL;

        const struct load_command *lc = (const struct load_command *)(header + 1);
        for (uint32_t i = 0; i < header->ncmds && lc; i++) {
            if (lc->cmd == LC_SYMTAB) {
                symtabCmd = (const struct symtab_command *)lc;
            } else if (lc->cmd == LC_FUNCTION_STARTS) {
                functionStartsCmd = (const struct linkedit_data_command *)lc;
            }
            if (lc->cmdsize == 0) {
                break;
            }
            lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
        }

        const uint8_t *linkedit = NULL;
        if (_hasLinkedit && _linkeditVmaddr != 0) {
            linkedit = (const uint8_t *)(uintptr_t)(_slide + _linkeditVmaddr);
        }

        // ---- LC_SYMTAB：名字 ----
        uint64_t symtabOffset = (symtabCmd && symtabCmd->symoff >= _linkeditFileoff)
            ? (uint64_t)(symtabCmd->symoff - _linkeditFileoff) : 0;
        uint64_t strtabOffset = (symtabCmd && symtabCmd->stroff >= _linkeditFileoff)
            ? (uint64_t)(symtabCmd->stroff - _linkeditFileoff) : 0;
        uint64_t symbolBytes = symtabCmd ? (uint64_t)symtabCmd->nsyms * sizeof(struct nlist_64) : 0;
        BOOL symtabInRange = (symtabCmd != NULL) &&
                             (_linkeditVmsize > 0) &&
                             (symtabOffset + symbolBytes <= _linkeditVmsize) &&
                             (strtabOffset + (uint64_t)symtabCmd->strsize <= _linkeditVmsize);

        if (linkedit && symtabCmd && symtabCmd->nsyms > 0 && symtabInRange) {
            const struct nlist_64 *nlist =
                (const struct nlist_64 *)(linkedit + (symtabCmd->symoff - _linkeditFileoff));
            const char *strtab = (const char *)(linkedit + (symtabCmd->stroff - _linkeditFileoff));
            size_t strsize = symtabCmd->strsize;

            size_t capacity = symtabCmd->nsyms;
            SSSymEntry *entries = (SSSymEntry *)malloc(sizeof(SSSymEntry) * capacity);
            size_t count = 0;

            if (entries) {
                for (uint32_t i = 0; i < symtabCmd->nsyms; i++) {
                    const struct nlist_64 *nl = &nlist[i];
                    if ((nl->n_type & N_STAB) != 0) continue;
                    if ((nl->n_type & N_TYPE) != N_SECT) continue;
                    if (nl->n_value == 0) continue;
                    if (nl->n_un.n_strx == 0 || nl->n_un.n_strx >= strsize) continue;

                    const char *symbolName = strtab + nl->n_un.n_strx;
                    if (!symbolName || !*symbolName) continue;
                    // 汇编器临时标签，不是函数
                    if (strncmp(symbolName, "ltmp", 4) == 0 ||
                        strncmp(symbolName, "loh", 3) == 0) {
                        continue;
                    }

                    entries[count].addr = nl->n_value + _slide;
                    entries[count].strx = nl->n_un.n_strx;
                    count++;
                }

                if (count > 0) {
                    qsort(entries, count, sizeof(SSSymEntry), SSSymEntryCompare);
                    _entries = entries;
                    _entryCount = count;
                    _strtab = strtab;
                    _strsize = strsize;
                } else {
                    free(entries);
                }
            }
        }

        // ---- LC_FUNCTION_STARTS：函数边界（ULEB128 增量）----
        uint64_t functionStartsOffset = (functionStartsCmd && functionStartsCmd->dataoff >= _linkeditFileoff)
            ? (uint64_t)(functionStartsCmd->dataoff - _linkeditFileoff) : 0;
        BOOL functionStartsInRange = (functionStartsCmd != NULL) &&
                                     (_linkeditVmsize > 0) &&
                                     (functionStartsOffset + functionStartsCmd->datasize <= _linkeditVmsize);

        if (linkedit && functionStartsCmd && functionStartsCmd->datasize > 0 && functionStartsInRange) {
            const uint8_t *cursor =
                linkedit + (functionStartsCmd->dataoff - _linkeditFileoff);
            const uint8_t *end = cursor + functionStartsCmd->datasize;

            uint64_t address = _textBase;
            size_t capacity = 256;
            size_t count = 0;
            uint64_t *starts = (uint64_t *)malloc(sizeof(uint64_t) * capacity);

            if (starts) {
                while (cursor < end) {
                    uint64_t delta = 0;
                    uint32_t shift = 0;
                    uint8_t byte = 0;
                    do {
                        if (cursor >= end) break;
                        byte = *cursor++;
                        delta |= (uint64_t)(byte & 0x7F) << shift;
                        shift += 7;
                    } while ((byte & 0x80) && shift < 64);

                    if (delta == 0) {
                        break;
                    }
                    address += delta;

                    if (count == capacity) {
                        size_t newCapacity = capacity * 2;
                        uint64_t *grown =
                            (uint64_t *)realloc(starts, sizeof(uint64_t) * newCapacity);
                        if (!grown) break;
                        starts = grown;
                        capacity = newCapacity;
                    }
                    starts[count++] = address;
                }

                if (count > 0) {
                    _functionStarts = starts;
                    _functionCount = count;
                } else {
                    free(starts);
                }
            }
        }
    }
}

@end

#pragma mark - Symbolicator

@interface SSSymbolicator () {
    NSMutableArray<SSImageSymbols *> *_images;
    NSMutableDictionary<NSNumber *, SSSymbol *> *_cache;
    BOOL _imagesLoaded;

    SSObjCMethodEntry *_objcEntries;
    size_t _objcEntryCount;
    BOOL _objcMethodsStarted;
    BOOL _objcMethodsReady;

    NSMutableDictionary<NSString *, NSString *> *_symbolOverrides;
    BOOL _symbolMapsLoaded;
}

- (void)startObjCMethodBuildIfNeeded;
- (void)buildObjCMethodTable;
- (void)finishObjCMethodBuildWithEntries:(SSObjCMethodEntry *)entries count:(size_t)count;
- (void)appendMethodsOfClass:(Class)cls
               isClassMethod:(BOOL)isClassMethod
                     entries:(SSObjCMethodEntry **)entriesPtr
                       count:(size_t *)countPtr
                    capacity:(size_t *)capacityPtr;
- (NSString *)objcMethodNameForIMP:(uint64_t)imp;

- (SSImageSymbols *)imageNamed:(NSString *)name;
- (NSString *)defaultSymbolModule;
- (NSString *)documentsPath;
- (NSString *)symbolOverridesPath;
- (uint64_t)symbolOffsetForAddress:(uint64_t)address inImage:(SSImageSymbols *)image;
- (void)addOverrideForAddress:(uint64_t)address name:(NSString *)name module:(NSString *)module;
- (NSString *)overrideNameForImage:(NSString *)imageName offset:(uint64_t)offset;
- (BOOL)parseHexAddress:(NSString *)token into:(uint64_t *)out;
- (NSUInteger)parseSymbolText:(NSString *)text module:(NSString *)module;
- (NSUInteger)parseSymbolJSONData:(NSData *)data module:(NSString *)module error:(NSError **)error;
- (void)didImportSymbols:(NSUInteger)count;
- (void)saveSymbolOverrides;
- (void)loadSymbolMapsFromDocumentsIfNeeded;

@end

@implementation SSSymbolicator

+ (instancetype)sharedInstance {
    static SSSymbolicator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSSymbolicator alloc] init];
    });
    return instance;
}

+ (instancetype)shared {
    return [self sharedInstance];
}

- (instancetype)init {
    if (self = [super init]) {
        _cache = [NSMutableDictionary dictionary];
        _symbolOverrides = [NSMutableDictionary dictionary];

        NSString *cachePath = [self symbolOverridesPath];
        if (cachePath.length > 0) {
            NSDictionary *cached = [NSDictionary dictionaryWithContentsOfFile:cachePath];
            if (cached.count > 0) {
                [_symbolOverrides addEntriesFromDictionary:cached];
            }
        }

        // Documents 下的 ss_symbols.json / ss_symbols.txt 只读一次，放后台解析
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self loadSymbolMapsFromDocumentsIfNeeded];
        });
    }
    return self;
}

#pragma mark - Image table

- (void)ensureImagesLoaded {
    @synchronized (self) {
        if (_imagesLoaded) {
            return;
        }
        _imagesLoaded = YES;

        NSMutableArray<SSImageSymbols *> *images = [NSMutableArray array];
        uint32_t imageCount = _dyld_image_count();

        for (uint32_t i = 0; i < imageCount; i++) {
            const struct mach_header_64 *header =
                (const struct mach_header_64 *)_dyld_get_image_header(i);
            if (!header || header->magic != MH_MAGIC_64) {
                continue;
            }

            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            uint64_t minAddress = UINT64_MAX;
            uint64_t maxAddress = 0;
            uint64_t textBase = 0;
            uint64_t linkeditVmaddr = 0;
            uint64_t linkeditFileoff = 0;
            uint64_t linkeditVmsize = 0;
            BOOL hasLinkedit = NO;

            const struct load_command *lc = (const struct load_command *)(header + 1);
            for (uint32_t j = 0; j < header->ncmds && lc; j++) {
                if (lc->cmd == LC_SEGMENT_64) {
                    const struct segment_command_64 *segment =
                        (const struct segment_command_64 *)lc;
                    // __PAGEZERO 的 initprot 是 0，不能算进镜像范围
                    BOOL usable = (segment->vmsize > 0) &&
                                  ((segment->initprot & (VM_PROT_READ | VM_PROT_EXECUTE)) != 0);
                    if (usable) {
                        uint64_t start = (uint64_t)((intptr_t)segment->vmaddr + slide);
                        uint64_t end = start + (uint64_t)segment->vmsize;
                        if (start < minAddress) minAddress = start;
                        if (end > maxAddress) maxAddress = end;
                    }
                    if (strcmp(segment->segname, "__TEXT") == 0) {
                        textBase = (uint64_t)((intptr_t)segment->vmaddr + slide);
                    } else if (strcmp(segment->segname, "__LINKEDIT") == 0) {
                        linkeditVmaddr = (uint64_t)segment->vmaddr;
                        linkeditFileoff = (uint64_t)segment->fileoff;
                        linkeditVmsize = (uint64_t)segment->vmsize;
                        hasLinkedit = YES;
                    }
                }
                if (lc->cmdsize == 0) {
                    break;
                }
                lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
            }

            if (minAddress == UINT64_MAX || maxAddress <= minAddress) {
                continue;
            }
            if (textBase == 0) {
                textBase = (uint64_t)(uintptr_t)header;
            }

            SSImageSymbols *image = [[SSImageSymbols alloc] init];
            image->_slide = (uint64_t)slide;
            image->_base = textBase;
            image->_end = maxAddress;
            image->_textBase = textBase;
            image->_headerAddress = (uint64_t)(uintptr_t)header;
            image->_linkeditVmaddr = linkeditVmaddr;
            image->_linkeditFileoff = linkeditFileoff;
            image->_linkeditVmsize = linkeditVmsize;
            image->_hasLinkedit = hasLinkedit;

            const char *path = _dyld_get_image_name(i);
            if (path) {
                image.path = [NSString stringWithUTF8String:path];
                image.name = [image.path lastPathComponent];
            }
            if (image.name.length == 0) {
                image.name = @"unknown";
            }

            [images addObject:image];
        }

        [images sortUsingComparator:^NSComparisonResult(SSImageSymbols *a, SSImageSymbols *b) {
            if (a->_base < b->_base) return NSOrderedAscending;
            if (a->_base > b->_base) return NSOrderedDescending;
            return NSOrderedSame;
        }];

        _images = images;
    }
}

- (SSImageSymbols *)imageContaining:(uint64_t)address {
    [self ensureImagesLoaded];

    NSArray<SSImageSymbols *> *images = _images;
    size_t count = images.count;
    if (count == 0) {
        return nil;
    }

    size_t lo = 0, hi = count;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (images[mid]->_base <= address) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo == 0) {
        return nil;
    }

    SSImageSymbols *image = images[lo - 1];
    if (address < image->_base || address >= image->_end) {
        return nil;
    }
    return image;
}

#pragma mark - Name lookup

- (NSString *)nameForEntry:(SSSymEntry)entry inImage:(SSImageSymbols *)image {
    if (!image->_strtab || entry.strx >= image->_strsize) {
        return nil;
    }
    const char *name = image->_strtab + entry.strx;
    if (!name || !*name) {
        return nil;
    }
    NSString *string = [NSString stringWithUTF8String:name];
    if (string.length == 0) {
        string = [NSString stringWithCString:name encoding:NSISOLatin1StringEncoding];
    }
    return string.length > 0 ? string : nil;
}

/// 函数 [start, end) 内、<= address 的最近符号
- (NSString *)nameInImage:(SSImageSymbols *)image
            functionStart:(uint64_t)functionStart
                  address:(uint64_t)address {
    if (image->_entryCount == 0) {
        return nil;
    }
    size_t index = SSSymUpperBound(image->_entries, image->_entryCount, address);
    if (index == 0) {
        return nil;
    }
    SSSymEntry entry = image->_entries[index - 1];
    if (entry.addr < functionStart) {
        return nil;
    }
    return [self nameForEntry:entry inImage:image];
}

#pragma mark - Public

- (SSSymbol *)symbolForAddress:(uint64_t)address {
    uint64_t normalized = SSStripPAC(address);
    if (normalized == 0) {
        return nil;
    }

    NSNumber *key = @(normalized);
    @synchronized (_cache) {
        SSSymbol *cached = _cache[key];
        if (cached) {
            return cached;
        }
    }

    SSSymbol *symbol = [self buildSymbolForDisplayAddress:normalized lookupAddress:normalized];

    // 没有真名的 sub_xxx 在 ObjC IMP 表就绪后可能变成 -[Class sel]，
    // 不能缓存，否则页面会一直拿到旧结果
    if (symbol.hasRealName) {
        @synchronized (_cache) {
            if (_cache.count > 2048) {
                [_cache removeAllObjects];
            }
            _cache[key] = symbol;
        }
    }
    return symbol;
}

- (SSSymbol *)symbolForReturnAddress:(uint64_t)address {
    uint64_t normalized = SSStripPAC(address);
    if (normalized == 0) {
        return nil;
    }
    // 返回地址指向「调用指令的下一条」，用 -1 落到调用点所在函数/指令
    uint64_t lookup = normalized > 0 ? normalized - 1 : normalized;
    return [self buildSymbolForDisplayAddress:normalized lookupAddress:lookup];
}

- (void)preloadForAddresses:(NSArray<NSNumber *> *)addresses {
    for (NSNumber *number in addresses) {
        [self symbolForAddress:number.unsignedLongLongValue];
    }
}

- (void)invalidateCache {
    @synchronized (_cache) {
        [_cache removeAllObjects];
    }
}

#pragma mark - ObjC IMP reverse lookup

- (void)startObjCMethodBuildIfNeeded {
    @synchronized (self) {
        if (_objcMethodsStarted) {
            return;
        }
        _objcMethodsStarted = YES;
    }

    // 枚举 ObjC runtime 可能有几十毫秒开销，放后台；页面收到完成通知后再刷新
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self buildObjCMethodTable];
    });
}

- (void)buildObjCMethodTable {
    @autoreleasepool {
        int classBufferCount = objc_getClassList(NULL, 0);
        if (classBufferCount <= 0) {
            [self finishObjCMethodBuildWithEntries:NULL count:0];
            return;
        }

        Class *classes = (Class *)malloc(sizeof(Class) * (size_t)classBufferCount);
        if (!classes) {
            [self finishObjCMethodBuildWithEntries:NULL count:0];
            return;
        }

        int classCount = objc_getClassList(classes, classBufferCount);
        if (classCount > classBufferCount) {
            classCount = classBufferCount;
        }

        size_t capacity = 1024;
        size_t count = 0;
        SSObjCMethodEntry *entries =
            (SSObjCMethodEntry *)malloc(sizeof(SSObjCMethodEntry) * capacity);

        if (entries) {
            for (int i = 0; i < classCount; i++) {
                Class cls = classes[i];
                [self appendMethodsOfClass:cls
                             isClassMethod:NO
                                   entries:&entries
                                     count:&count
                                  capacity:&capacity];

                Class metaClass = object_getClass(cls);
                if (metaClass && metaClass != cls) {
                    [self appendMethodsOfClass:metaClass
                                 isClassMethod:YES
                                       entries:&entries
                                         count:&count
                                      capacity:&capacity];
                }
            }

            if (count > 0) {
                qsort(entries, count, sizeof(SSObjCMethodEntry), SSObjCMethodEntryCompare);
            }
        }

        free(classes);
        [self finishObjCMethodBuildWithEntries:entries count:count];
    }
}

- (void)finishObjCMethodBuildWithEntries:(SSObjCMethodEntry *)entries count:(size_t)count {
    @synchronized (self) {
        _objcEntries = entries;
        _objcEntryCount = count;
        _objcMethodsReady = YES;
    }

    // 之前缓存的 sub_xxx 需要重算，否则页面会一直拿到旧结果
    [self invalidateCache];

    [LoggingService log:@"[符号] ObjC IMP 表构建完成: %lu 个方法", (unsigned long)count];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:SSSymbolicatorObjCMethodsDidBecomeReadyNotification
                          object:self];
    });
}

- (void)appendMethodsOfClass:(Class)cls
               isClassMethod:(BOOL)isClassMethod
                     entries:(SSObjCMethodEntry **)entriesPtr
                       count:(size_t *)countPtr
                    capacity:(size_t *)capacityPtr {
    if (!cls) {
        return;
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    if (!methods) {
        return;
    }

    const char *className = class_getName(cls);

    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        IMP imp = method_getImplementation(method);
        SEL selector = method_getName(method);
        if (!imp || !selector) {
            continue;
        }

        const char *selectorName = sel_getName(selector);
        if (!selectorName || !*selectorName) {
            continue;
        }

        if (*countPtr == *capacityPtr) {
            size_t newCapacity = (*capacityPtr) * 2;
            SSObjCMethodEntry *grown =
                (SSObjCMethodEntry *)realloc(*entriesPtr, sizeof(SSObjCMethodEntry) * newCapacity);
            if (!grown) {
                free(methods);
                return;
            }
            *entriesPtr = grown;
            *capacityPtr = newCapacity;
        }

        SSObjCMethodEntry *entry = &(*entriesPtr)[(*countPtr)++];
        entry->imp = SSStripPAC((uint64_t)(uintptr_t)imp);
        entry->className = className;
        entry->selectorName = selectorName;
        entry->isClassMethod = isClassMethod ? 1 : 0;
    }

    free(methods);
}

- (NSString *)objcMethodNameForIMP:(uint64_t)imp {
    if (imp == 0) {
        return nil;
    }

    // 只有真正遇到「nlist 里没有名字」的地址时才启动枚举，避免无谓开销
    [self startObjCMethodBuildIfNeeded];

    uint64_t target = SSStripPAC(imp);

    SSObjCMethodEntry *entries = NULL;
    size_t count = 0;
    BOOL ready = NO;
    @synchronized (self) {
        entries = _objcEntries;
        count = _objcEntryCount;
        ready = _objcMethodsReady;
    }
    if (!ready || !entries || count == 0) {
        return nil;
    }

    size_t lo = 0, hi = count;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (entries[mid].imp < target) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo >= count || entries[lo].imp != target) {
        return nil;
    }

    size_t first = lo;
    while (first > 0 && entries[first - 1].imp == target) {
        first--;
    }
    size_t last = lo;
    while (last + 1 < count && entries[last + 1].imp == target) {
        last++;
    }

    // 同一个 IMP 对应多个方法（空方法 / 转发桩 / 别名）时，名字不可信，不猜
    if (last != first) {
        return nil;
    }

    const SSObjCMethodEntry *entry = &entries[lo];
    return [NSString stringWithFormat:@"%c[%s %s]",
            entry->isClassMethod ? '+' : '-',
            entry->className,
            entry->selectorName];
}

#pragma mark - External symbol maps

- (NSString *)documentsPath {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

- (NSString *)symbolOverridesPath {
    NSString *documents = [self documentsPath];
    return documents.length > 0 ? [documents stringByAppendingPathComponent:@"ss_symbol_overrides.plist"] : nil;
}

- (SSImageSymbols *)imageNamed:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    [self ensureImagesLoaded];

    NSString *base = [name lastPathComponent];
    for (SSImageSymbols *image in _images) {
        if ([image.name isEqualToString:name] || [image.name isEqualToString:base]) {
            return image;
        }
        if ([image.name caseInsensitiveCompare:name] == NSOrderedSame ||
            [image.name caseInsensitiveCompare:base] == NSOrderedSame) {
            return image;
        }
    }
    return nil;
}

- (NSString *)defaultSymbolModule {
    SSImageSymbols *unity = [self imageNamed:@"UnityFramework"];
    if (unity) {
        return unity.name;
    }

    [self ensureImagesLoaded];
    const struct mach_header *mainHeader = _dyld_get_image_header(0);
    if (mainHeader) {
        uint64_t address = (uint64_t)(uintptr_t)mainHeader;
        for (SSImageSymbols *image in _images) {
            if (image->_headerAddress == address) {
                return image.name;
            }
        }
    }
    return _images.firstObject.name ?: @"";
}

/// 输入可能是未滑动 VA、运行时地址或 RVA，统一成「相对 __TEXT 基址的偏移」
- (uint64_t)symbolOffsetForAddress:(uint64_t)address inImage:(SSImageSymbols *)image {
    if (!image) {
        return address;
    }
    if (address >= image->_base && address < image->_end) {
        return address - image->_base;              // 运行时地址
    }

    uint64_t unslidBase = image->_base - image->_slide;
    uint64_t size = image->_end > image->_base ? image->_end - image->_base : 0;
    if (address >= unslidBase && address < unslidBase + size) {
        return address - unslidBase;                // 未滑动 VA（主二进制常见 0x100...）
    }
    if (address < size) {
        return address;                             // 直接给的 RVA / 偏移
    }
    return address;
}

- (void)addOverrideForAddress:(uint64_t)address name:(NSString *)name module:(NSString *)module {
    if (name.length == 0) {
        return;
    }
    NSString *moduleName = module.length > 0 ? module : [self defaultSymbolModule];
    if (moduleName.length == 0) {
        return;
    }

    SSImageSymbols *image = [self imageNamed:moduleName];
    NSString *resolvedModule = image.name.length > 0 ? image.name : moduleName;
    uint64_t offset = [self symbolOffsetForAddress:address inImage:image];
    NSString *key = [NSString stringWithFormat:@"%@|0x%llX", resolvedModule, offset];

    @synchronized (self) {
        _symbolOverrides[key] = name;
    }
}

- (NSString *)overrideNameForImage:(NSString *)imageName offset:(uint64_t)offset {
    if (imageName.length == 0) {
        return nil;
    }
    NSString *key = [NSString stringWithFormat:@"%@|0x%llX", imageName, offset];
    @synchronized (self) {
        return _symbolOverrides[key];
    }
}

- (BOOL)parseHexAddress:(NSString *)token into:(uint64_t *)out {
    if (!out) {
        return NO;
    }
    NSString *value = token;
    if ([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"]) {
        value = [value substringFromIndex:2];
    }
    if (value.length == 0) {
        return NO;
    }

    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned long long address = 0;
    if (![scanner scanHexLongLong:&address] || !scanner.isAtEnd) {
        return NO;
    }
    *out = (uint64_t)address;
    return YES;
}

- (NSUInteger)parseSymbolText:(NSString *)text module:(NSString *)module {
    if (text.length == 0) {
        return 0;
    }

    NSUInteger count = 0;
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0 || [line hasPrefix:@"#"] || [line hasPrefix:@"//"]) {
            continue;
        }

        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (NSString *token in [line componentsSeparatedByCharactersInSet:whitespace]) {
            if (token.length > 0) {
                [parts addObject:token];
            }
        }
        if (parts.count < 2) {
            continue;
        }

        NSString *first = parts[0];
        NSString *lineModule = module;
        NSString *addressToken = first;

        NSRange plus = [first rangeOfString:@"+"];
        if (plus.location != NSNotFound && plus.location > 0 && plus.location + 1 < first.length) {
            lineModule = [first substringToIndex:plus.location];
            addressToken = [first substringFromIndex:plus.location + 1];
        }

        NSUInteger nameStart = 1;
        if (parts.count >= 3 && parts[1].length == 1) {
            unichar type = [parts[1] characterAtIndex:0];
            const char *nmTypes = "TtUuDdBbRrSsWwVv?";
            if (type < 128 && strchr(nmTypes, (char)type) != NULL) {
                nameStart = 2;   // nm 风格：0000... T _name
            }
        }
        if (nameStart >= parts.count) {
            continue;
        }

        NSString *name = [[parts subarrayWithRange:NSMakeRange(nameStart, parts.count - nameStart)]
                          componentsJoinedByString:@" "];
        if (name.length == 0) {
            continue;
        }

        uint64_t address = 0;
        if (![self parseHexAddress:addressToken into:&address]) {
            continue;
        }

        [self addOverrideForAddress:address name:name module:lineModule];
        count++;
    }

    return count;
}

- (NSUInteger)parseSymbolJSONData:(NSData *)data module:(NSString *)module error:(NSError **)error {
    NSError *jsonError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!root) {
        if (error) {
            *error = jsonError;
        }
        return 0;
    }

    NSArray *methods = nil;
    if ([root isKindOfClass:[NSDictionary class]]) {
        id value = ((NSDictionary *)root)[@"ScriptMethod"];
        if ([value isKindOfClass:[NSArray class]]) {
            methods = value;
        }
    } else if ([root isKindOfClass:[NSArray class]]) {
        methods = root;
    }
    if (!methods) {
        return 0;
    }

    NSUInteger count = 0;
    for (id item in methods) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *entry = item;

        id addressValue = entry[@"Address"];
        NSString *name = entry[@"Name"];
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            continue;
        }

        uint64_t address = 0;
        if ([addressValue isKindOfClass:[NSNumber class]]) {
            address = [addressValue unsignedLongLongValue];
        } else if ([addressValue isKindOfClass:[NSString class]]) {
            if (![self parseHexAddress:addressValue into:&address]) {
                continue;
            }
        } else {
            continue;
        }

        NSString *displayName = name;
        id typeName = entry[@"TypeName"];
        if ([typeName isKindOfClass:[NSString class]] && ((NSString *)typeName).length > 0) {
            displayName = [NSString stringWithFormat:@"%@::%@", typeName, name];
        }

        [self addOverrideForAddress:address name:displayName module:module];
        count++;
    }
    return count;
}

- (NSUInteger)importSymbolMapAtPath:(NSString *)path
                             module:(NSString *)moduleName
                              error:(NSError **)error {
    if (path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SSSymbolicator"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"路径为空"}];
        }
        return 0;
    }

    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (data.length == 0) {
        return 0;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger index = 0;
    while (index < data.length &&
           (bytes[index] == ' ' || bytes[index] == '\t' ||
            bytes[index] == '\r' || bytes[index] == '\n')) {
        index++;
    }
    BOOL looksLikeJSON = (index < data.length && (bytes[index] == '{' || bytes[index] == '['));

    NSUInteger count = 0;
    if (looksLikeJSON) {
        count = [self parseSymbolJSONData:data module:moduleName error:error];
    } else {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) {
            text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        }
        count = [self parseSymbolText:text module:moduleName];
    }

    if (count > 0) {
        [self didImportSymbols:count];
    }
    return count;
}

- (NSUInteger)importSymbolMapText:(NSString *)text module:(NSString *)moduleName {
    NSUInteger count = [self parseSymbolText:text module:moduleName];
    if (count > 0) {
        [self didImportSymbols:count];
    }
    return count;
}

- (BOOL)setSymbolName:(NSString *)name forAddress:(uint64_t)address {
    if (name.length == 0 || address == 0) {
        return NO;
    }

    SSImageSymbols *image = [self imageContaining:address];
    if (!image || image.name.length == 0) {
        return NO;
    }
    [image buildIfNeeded];

    uint64_t functionStart = address;
    if (image->_functionCount > 0) {
        size_t index = SSUpperBoundU64(image->_functionStarts, image->_functionCount, address);
        if (index > 0) {
            functionStart = image->_functionStarts[index - 1];
        }
    }

    [self addOverrideForAddress:functionStart name:name module:image.name];
    [self didImportSymbols:1];
    return YES;
}

- (void)clearImportedSymbols {
    @synchronized (self) {
        [_symbolOverrides removeAllObjects];
    }
    [self invalidateCache];
    [self saveSymbolOverrides];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center postNotificationName:SSSymbolicatorDidUpdateSymbolsNotification object:self];
        [center postNotificationName:SSSymbolicatorObjCMethodsDidBecomeReadyNotification object:self];
    });
}

- (void)didImportSymbols:(NSUInteger)count {
    if (count == 0) {
        return;
    }

    [self invalidateCache];
    [self saveSymbolOverrides];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center postNotificationName:SSSymbolicatorDidUpdateSymbolsNotification object:self];
        // 兼容现有页面：它们监听的是 ObjC 表就绪通知，用来做「符号变了，刷新」
        [center postNotificationName:SSSymbolicatorObjCMethodsDidBecomeReadyNotification object:self];
    });
}

- (void)saveSymbolOverrides {
    NSDictionary *snapshot = nil;
    @synchronized (self) {
        snapshot = [_symbolOverrides copy];
    }

    NSString *path = [self symbolOverridesPath];
    if (path.length == 0) {
        return;
    }

    static dispatch_queue_t saveQueue = NULL;
    static dispatch_once_t saveOnce;
    dispatch_once(&saveOnce, ^{
        saveQueue = dispatch_queue_create("com.ss.symbol.save", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(saveQueue, ^{
        [snapshot writeToFile:path atomically:YES];
    });
}

- (void)loadSymbolMapsFromDocumentsIfNeeded {
    @synchronized (self) {
        if (_symbolMapsLoaded) {
            return;
        }
        _symbolMapsLoaded = YES;
    }

    NSString *documents = [self documentsPath];
    if (documents.length == 0) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSUInteger total = 0;

    // 可选：ss_symbols.module 指定映射归属的模块（Unity 常见 UnityFramework / 主二进制）
    NSString *moduleHint = nil;
    NSString *modulePath = [documents stringByAppendingPathComponent:@"ss_symbols.module"];
    if ([fileManager fileExistsAtPath:modulePath]) {
        NSString *moduleText = [NSString stringWithContentsOfFile:modulePath
                                                         encoding:NSUTF8StringEncoding
                                                            error:NULL];
        moduleHint = [moduleText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (moduleHint.length == 0) {
            moduleHint = nil;
        }
    }

    NSString *jsonPath = [documents stringByAppendingPathComponent:@"ss_symbols.json"];
    if ([fileManager fileExistsAtPath:jsonPath]) {
        total += [self importSymbolMapAtPath:jsonPath module:moduleHint error:NULL];
    }

    NSString *textPath = [documents stringByAppendingPathComponent:@"ss_symbols.txt"];
    if ([fileManager fileExistsAtPath:textPath]) {
        NSData *data = [NSData dataWithContentsOfFile:textPath];
        if (data.length > 0) {
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (text.length > 0) {
                total += [self importSymbolMapText:text module:moduleHint];
            }
        }
    }

    if (total > 0) {
        [LoggingService log:@"[符号] Documents 外部映射已加载: %lu 条", (unsigned long)total];
    }
}

#pragma mark - Core

- (SSSymbol *)buildSymbolForDisplayAddress:(uint64_t)address lookupAddress:(uint64_t)lookup {
    SSImageSymbols *image = [self imageContaining:lookup];

    SSSymbol *symbol = [[SSSymbol alloc] init];
    symbol.address = address;

    if (!image) {
        return symbol;
    }

    symbol.imageBase = image->_base;
    symbol.imageName = image.name;
    symbol.imageOffset = address >= image->_base ? address - image->_base : 0;

    [image buildIfNeeded];

    NSString *name = nil;

    if (image->_functionCount > 0) {
        size_t index = SSUpperBoundU64(image->_functionStarts, image->_functionCount, lookup);
        if (index > 0) {
            uint64_t functionStart = image->_functionStarts[index - 1];
            // 外部导入的符号优先级最高（Il2CppDumper / dSYM / 手动命名）
            name = [self overrideNameForImage:image.name offset:functionStart - image->_base];
            if (!name) {
                name = [self nameInImage:image functionStart:functionStart address:lookup];
            }
            if (!name) {
                // 被 strip 的 ObjC 包：nlist 没有方法符号，用 runtime 的 IMP 反查
                name = [self objcMethodNameForIMP:functionStart];
            }
            if (!name) {
                name = [NSString stringWithFormat:@"sub_%llX", functionStart - image->_base];
            }
            symbol.functionStart = functionStart;
            symbol.functionOffset = address >= functionStart ? address - functionStart : 0;
        }
    } else if (image->_entryCount > 0) {
        // 没有函数起点表时退化为「最近符号」，但距离太远就不认
        size_t index = SSSymUpperBound(image->_entries, image->_entryCount, lookup);
        if (index > 0) {
            SSSymEntry entry = image->_entries[index - 1];
            if (lookup - entry.addr <= 0x20000) {
                // 外部映射优先于「最近符号」的猜测
                name = [self overrideNameForImage:image.name offset:entry.addr - image->_base];
                if (!name) {
                    name = [self nameForEntry:entry inImage:image];
                }
                symbol.functionStart = entry.addr;
                symbol.functionOffset = address >= entry.addr ? address - entry.addr : 0;
            }
        }
    }

    if (!name) {
        // 没有函数起点/最近符号时，先试外部映射的精确偏移
        name = [self overrideNameForImage:image.name offset:lookup - image->_base];
        if (name.length > 0 && symbol.functionStart == 0) {
            symbol.functionStart = lookup;
            symbol.functionOffset = 0;
        }
    }

    if (!name) {
        // 最后试一次 ObjC IMP（可能是方法入口）
        name = [self objcMethodNameForIMP:lookup];
        if (name.length > 0 && symbol.functionStart == 0) {
            symbol.functionStart = lookup;
            symbol.functionOffset = 0;
        }
    }

    if (name.length > 0) {
        symbol.rawName = name;
        symbol.hasRealName = ![name hasPrefix:@"sub_"];
        SSSymbolKind kind = SSSymbolKindUnknown;
        symbol.displayName = SSDemangleName(name, &kind);
        symbol.kind = kind;
    }

    return symbol;
}

@end
