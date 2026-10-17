#import "Modules/MemoryAnalysis/PtrScanBridge.h"
#import "Services/LogService.h"

#import <mach/mach.h>
#import <mach/vm_region.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <unistd.h>

extern "C" {
#include "fs_ptrscan.h"
#include "ptr_index.h"
#include "pc_list.h"
#include "vma/vm_area.h"
#include "vma/vma_map.h"
#include "vma/vma_select.h"
#include "platform/plat_mach.h"     /* mach_vm_region：iPhoneOS SDK 里没有这个头 */
#include "platform/plat_proc.h"
}

static NSString *const kPtrScanErrorDomain = @"PtrScan";

/* 库读目标进程内存的回调：就是平台层自己的 readv */
static ssize_t ptr_scan_reader(pid_t pid,
                               const struct iovec *local_iov, unsigned long liovcnt,
                               const struct iovec *remote_iov, unsigned long riovcnt,
                               void *userdata)
{
    (void)userdata;
    return plat_proc_readv(pid, local_iov, liovcnt, remote_iov, riovcnt);
}

/*
 * 区域表由本层自己建，**不用**库的 parse_maps()。
 *
 * 原因：iOS 上库的 parse_maps() 会调 proc_regionfilename() 取区域路径，而这个
 * 调用在被注入的进程里会直接把 App 打成 SIGBUS（真机崩溃日志：
 *   proc_regionfilename <- plat_proc_maps <- -[PtrScanBridge runScan:]，
 *   EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE）。
 *
 * 这里改用 mach_vm_region()：它是普通的映射查询（不递归子映射、不会像
 * mach_vm_region_recurse() 那样在 pvz 上卡死），路径则从 dyld 镜像表按地址
 * 区间匹配，这本来就是 iOS 上更可靠的来源。
 */

#define BRIDGE_IMAGE_MAX 1024
#define TL_LAYER_MAX     16

struct bridge_image {
    uint64_t start;
    uint64_t end;
    char     path[1024];
};

static int bridge_collect_images(struct bridge_image *out, int max)
{
    int      n     = 0;
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count && n < max; i++) {
        const struct mach_header_64 *h =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        const char *name = _dyld_get_image_name(i);

        if (!h || !name)
            continue;

        uint64_t minv = UINT64_MAX, maxv = 0;
        const uint8_t *p = (const uint8_t *)h + sizeof(*h);

        for (uint32_t c = 0; c < h->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)p;

            if (lc->cmdsize == 0)
                break;

            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *s =
                    (const struct segment_command_64 *)lc;

                if (s->vmsize > 0) {
                    if (s->vmaddr < minv)
                        minv = s->vmaddr;
                    if (s->vmaddr + s->vmsize > maxv)
                        maxv = s->vmaddr + s->vmsize;
                }
            }
            p += lc->cmdsize;
        }

        if (minv == UINT64_MAX || maxv <= minv)
            continue;

        /* 镜像头是加载后的地址，段 vmaddr 是文件/缓存内偏移，两者相减就是加载基址；
         * 共享缓存里的 dylib 也成立（段 vmaddr 就是缓存内偏移）。 */
        out[n].start = (uint64_t)(uintptr_t)h - minv;
        out[n].end   = out[n].start + (maxv - minv);
        snprintf(out[n].path, sizeof(out[n].path), "%s", name);
        n++;
    }
    return n;
}

static const char *bridge_path_for(uint64_t addr, const struct bridge_image *imgs, int n)
{
    for (int i = 0; i < n; i++) {
        if (addr >= imgs[i].start && addr < imgs[i].end)
            return imgs[i].path;
    }
    return NULL;
}

/*
 * 说明：库在 iOS 上用 proc_regionfilename() 给区域取路径。之前这个符号被本工程
 * 调试器里的同名全局变量劫持（DynaDbg/native_api.mm），导致库把数据当地址调用
 * 而 SIGBUS；那个变量已改名为 g_proc_regionfilename，冲突消失，所以这里**不再**
 * 自己实现同名函数 —— 直接用系统的那一份，插件与命令行走的路径就完全一致
 * （命令行在真机上验证：同一进程同一地址，层 1 命中 6、5 层 191 条链）。
 */

/* 区域过滤：可写 / 单区上限 / 排除名单。skipWritable 用于"只扫可写"失败后的重试。 */
static void bridge_apply_filters(struct vm_area **vma, PtrScanOptions *o, int skipWritable)
{
    if (!skipWritable && o.writableOnly)
        vma_filter_writable(vma);

    if (o.maxRegion > 0)
        vma_filter_max_region(vma, o.maxRegion);

    if (o.excludeNames.count > 0) {
        const char *specs[32];
        int n = 0;

        for (NSString *s in o.excludeNames) {
            if (n >= 32)
                break;
            specs[n++] = s.UTF8String;
        }

        struct vma_select **sel = to_vma_select(specs, n);

        if (sel) {
            vma_filter_exclude(vma, sel, n);
            free_vma_select(sel, n);
        }
    }
}

static struct vm_area *bridge_build_vma(pid_t pid)
{
    mach_port_t task = (pid == getpid()) ? mach_task_self() : plat_mach_task(pid);

    if (task == MACH_PORT_NULL)
        return NULL;

    /*
     * 注意：这张表约 1 MB（1024 × 每个 1 KB 的路径），必须放堆上。
     * 之前放在栈上，而本函数跑在 GCD 工作线程（栈只有 ~512 KB）上，
     * 一进入就爆栈：真机日志 SIGBUS / KERN_PROTECTION_FAILURE，栈地址
     * 0x16f76c0b8，调用栈 bridge_collect_images <- bridge_build_vma。
     */
    struct bridge_image *imgs =
        (struct bridge_image *)calloc(BRIDGE_IMAGE_MAX, sizeof(struct bridge_image));
    int nimg = imgs ? bridge_collect_images(imgs, BRIDGE_IMAGE_MAX) : 0;

    struct vm_area *head = NULL, *tail = NULL;
    mach_vm_address_t addr = 0;
    long guard = 0;

    while (guard++ < (1 << 20)) {
        mach_vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t obj = MACH_PORT_NULL;

        memset(&info, 0, sizeof(info));

        kern_return_t kr = mach_vm_region(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                          (vm_region_info_t)&info, &cnt, &obj);
        if (obj != MACH_PORT_NULL)
            mach_port_deallocate(mach_task_self(), obj);
        if (kr != KERN_SUCCESS || size == 0)
            break;

        struct vm_area *v = (struct vm_area *)calloc(1, sizeof(*v));

        if (!v)
            break;

        v->start   = (uint64_t)addr;
        v->end     = (uint64_t)addr + (uint64_t)size;
        v->perm[0] = (info.protection & VM_PROT_READ)    ? 'r' : '-';
        v->perm[1] = (info.protection & VM_PROT_WRITE)   ? 'w' : '-';
        v->perm[2] = (info.protection & VM_PROT_EXECUTE) ? 'x' : '-';
        v->perm[3] = (info.shared) ? 's' : 'p';
        v->perm[4] = '\0';
        v->offset  = (off_t)info.offset;

        const char *p = nimg ? bridge_path_for((uint64_t)addr, imgs, nimg) : NULL;

        if (p)
            v->pathname = strdup(p);

        if (tail)
            tail->next = v;
        else
            head = v;
        tail = v;

        addr += size;
    }

    free(imgs);
    return head;
}

@implementation PtrScanOptions
@end

@implementation PtrScanResult
@end

@interface PtrScanBridge ()
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, assign) BOOL cancelRequested;
@property (nonatomic, assign) struct idx_progress *idxProgress;
@property (nonatomic, assign) struct fs_progress *fsProgress;
@property (nonatomic, strong) NSDate *startedAt;

/* 索引缓存：同一套过滤条件 + 同一 pid 时复用 */
@property (nonatomic, assign) struct idx *cachedIdx;
@property (nonatomic, assign) pid_t       cachedPID;
@property (nonatomic, copy)   NSString   *cachedFilters;
@end

@implementation PtrScanBridge

+ (instancetype)sharedBridge {
    static PtrScanBridge *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[PtrScanBridge alloc] init]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _scanning = NO;
    }
    return self;
}

- (NSString *)resultsPath {
    /*
     * 文件名：pointer_scan_<UUID前8位>-<日期>-<时间>.txt
     * 例：pointer_scan_BDE65B0C-20261016-024133.txt
     * 带上时间戳后，多次扫描的结果在文件列表里按时间可辨（也仍然以
     * pointer_scan_ 开头，FilterPage 的文件选择器照旧能列出）。
     */
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale     = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";

    NSString *stamp = [fmt stringFromDate:[NSDate date]];
    NSString *uuid  = [[NSUUID UUID] UUIDString];
    NSString *short8 = uuid.length >= 8 ? [uuid substringToIndex:8] : uuid;

    NSString *name = [NSString stringWithFormat:@"pointer_scan_%@-%@.txt", short8, stamp];

    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

/* 库给的是模块路径，App 里用模块名（FilterPage 的 moduleBaseForName: 按
 * lastPathComponent / 后缀匹配），所以取最后一段。 */
- (NSString *)moduleNameForPath:(const char *)path {
    if (!path || !path[0]) return @"<anon>";
    NSString *full = [NSString stringWithUTF8String:path];
    NSString *last = full.lastPathComponent;
    return last.length ? last : full;
}

- (void)setEnvInt:(NSString *)name value:(uint64_t)value {
    setenv(name.UTF8String,
           [NSString stringWithFormat:@"%llu", (unsigned long long)value].UTF8String, 1);
}

- (NSString *)filterSignatureForOptions:(PtrScanOptions *)o
{
    return [NSString stringWithFormat:@"%d|%d|%llu|%@|%d|%d",
            (int)o.targetPID, o.writableOnly ? 1 : 0,
            (unsigned long long)o.maxRegion,
            [o.excludeNames componentsJoinedByString:@","] ?: @"",
            o.jobs, o.lowMemory ? 1 : 0];
}

- (NSString *)latestResultsPath {
    NSString *dir = NSTemporaryDirectory();
    NSArray<NSString *> *entries = [[NSFileManager defaultManager]
                                    contentsOfDirectoryAtPath:dir error:NULL];
    NSString *best = nil;
    NSDate   *bestDate = nil;

    for (NSString *name in entries) {
        if (!(([name hasPrefix:@"pointer_scan_"] || [name hasPrefix:@"pointer_chain_"]) &&
              [name hasSuffix:@".txt"]))
            continue;

        NSString *full = [dir stringByAppendingPathComponent:name];
        NSDate *mtime = [[[NSFileManager defaultManager] attributesOfItemAtPath:full error:NULL]
                         objectForKey:NSFileModificationDate];

        if (!best || (mtime && (!bestDate || [mtime compare:bestDate] == NSOrderedDescending))) {
            best     = full;
            bestDate = mtime;
        }
    }
    return best;
}

- (void)invalidateIndexCache {
    @synchronized (self) {
        if (self.cachedIdx) {
            idx_free(self.cachedIdx);
            self.cachedIdx = NULL;
        }
        self.cachedPID     = 0;
        self.cachedFilters = nil;
    }
    [LoggingService log:@"[指针扫描] 已清空索引缓存，下次会重建"];
}

- (void)stop {
    @synchronized (self) {
        self.cancelRequested = YES;
        if (self.idxProgress) idx_progress_cancel(self.idxProgress);
        if (self.fsProgress)  fs_progress_cancel(self.fsProgress);
    }
}

- (NSError *)errorWithText:(NSString *)text {
    return [NSError errorWithDomain:kPtrScanErrorDomain code:1
                           userInfo:@{NSLocalizedDescriptionKey: text}];
}

/* 结果里有没有链（有就不用再调参重试） */
static int bridge_has_chains(const struct fs_result *fr)
{
    if (!fr)
        return 0;

    for (const struct pc_list *g = fr->chains; g; g = g->next) {
        for (const struct oc_block *b = g->chains; b; b = b->next) {
            if (atomic_load(&b->used) > 0)
                return 1;
        }
    }
    return 0;
}

- (PtrScanResult *)runScan:(PtrScanOptions *)o
                  progress:(void (^)(float, NSString *))progress
                     error:(NSError **)error
{
    PtrScanResult *result = [[PtrScanResult alloc] init];
    pid_t pid = o.targetPID > 0 ? o.targetPID : getpid();

    if (o.targetAddress == 0) {
        if (error) *error = [self errorWithText:@"请输入有效的目标地址"];
        return nil;
    }

    /* 库的环境开关必须在建索引之前设好 */
    if (o.lowMemory) setenv("PTRSCAN_LOW_MEMORY", "1", 1);
    if (o.maxEdges) [self setEnvInt:@"PTRSCAN_MAX_EDGES" value:o.maxEdges];
    if (o.maxHits)  [self setEnvInt:@"PTRSCAN_MAX_HITS"  value:o.maxHits];

    NSString *path = [self resultsPath];
    if (![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]) {
        if (error) *error = [self errorWithText:@"无法创建结果文件"];
        return nil;
    }

    [LoggingService log:@"[指针扫描] 指针链模块 0CA2-4AD8-8E17-C3746067D85A  构建于 %s", __DATE__ " " __TIME__];
    [LoggingService log:@"[指针扫描] 引擎 libptrscan, pid=%d 目标=0x%llX 层数=%d 窗口=0x%llX k=%d",
     (int)pid, (unsigned long long)o.targetAddress,
     o.maxDepth, (unsigned long long)o.maxOffset, o.maxTargetsPerNode];

    /* 1. 内存区域表 + 过滤 + 分类 */
    if (progress) progress(0.02f, @"读取内存映射…");

    /*
     * 区域表用库自己的 parse_maps()：它就是命令行验证过的枚举（递归子映射、
     * 带看门狗），路径则由上面那个 proc_regionfilename 提供。之前这里换成过
     * 自己写的 mach_vm_region 版本，虽然不崩，但枚举结果和命令行不一致，
     * 导致"层 1 命中 0"。
     */
    struct vm_area *vma = NULL;
    if (parse_maps(pid, &vma) != 0) {
        vma = bridge_build_vma(pid);
        if (vma)
            [LoggingService log:@"[指针扫描] 库的区域枚举失败，已退回自建区域表"];
    }
    if (!vma) {
        if (error) *error = [self errorWithText:
            [NSString stringWithFormat:@"无法读取进程 %d 的内存映射", (int)pid]];
        return nil;
    }

    bridge_apply_filters(&vma, o, 0);

    /* 分类：iOS 上必须带 reader 从目标进程读镜像头，否则共享缓存里的 dylib
     * 会报出共享缓存文件偏移，模块基址就是错的。 */
    vma_image(vma, pid, ptr_scan_reader, NULL);

    uint32_t regions = 0;
    uint64_t bytes = 0;
    for (struct vm_area *v = vma; v; v = v->next) {
        regions++;
        bytes += v->end - v->start;
    }

    /* 诊断：锚点要求"有路径 + 段类型 DATA/BSS"，路径现在来自 dyld 匹配 */
    uint32_t with_path = 0, data_bss = 0, writable = 0;

    for (struct vm_area *v = vma; v; v = v->next) {
        if (v->pathname)
            with_path++;
        if (v->perm[1] == 'w')
            writable++;
        if (v->seg_type == VMA_TYPE_DATA || v->seg_type == VMA_TYPE_BSS)
            data_bss++;
    }

    [LoggingService log:@"[指针扫描] 区域 %u 个 / %.0f MB：有路径 %u，可写 %u，DATA/BSS(可做锚点) %u",
     regions, (double)bytes / 1048576.0, with_path, writable, data_bss];

    if (progress) progress(0.05f, [NSString stringWithFormat:
        @"索引 %u 个区域 / %.0f MB…", regions, (double)bytes / 1048576.0]);

    /* 2. 索引：能复用就复用（建一次要 ~20 秒，被扫的地址在这期间会变） */
    NSString *sig = [self filterSignatureForOptions:o];
    int       ownsIndex = 0;
    struct idx *ix = NULL;

    if (self.cachedIdx && self.cachedPID == pid &&
        [self.cachedFilters isEqualToString:sig]) {
        ix = self.cachedIdx;
        result.indexEntries  = (NSUInteger)idx_count(ix);
        result.indexSegments = (NSUInteger)idx_seg_count(ix);
        [LoggingService log:@"[指针扫描] 复用索引 %lu 槽（省掉重建的 20 秒，地址还是新鲜的）",
         (unsigned long)result.indexEntries];
    }

    struct idx_progress *ip = ix ? NULL : idx_progress_create();
    if (!ip) {
        free_vm_area(vma);
        if (error) *error = [self errorWithText:@"内存不足（进度对象）"];
        return nil;
    }
    @synchronized (self) { self.idxProgress = ip; }

    __block BOOL finished = NO;
    dispatch_queue_t pollQueue = dispatch_queue_create("ptrscan.progress", DISPATCH_QUEUE_SERIAL);
    dispatch_async(pollQueue, ^{
        while (!finished) {
            struct idx_progress_info info;
            idx_progress_get(ip, &info);
            if (progress) {
                float p = info.total_bytes
                        ? (float)((double)info.scanned_bytes / (double)info.total_bytes)
                        : 0.0f;
                progress(0.05f + p * 0.45f,
                         [NSString stringWithFormat:@"建立索引 %.0f%%（%llu 个指针槽）",
                          p * 100.0f, (unsigned long long)info.total_entries]);
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });

    if (!ix) {
        ix = idx_build(pid, vma, ptr_scan_reader, NULL, o.jobs, ip);
        ownsIndex = 1;
        finished = YES;
    }

    @synchronized (self) { self.idxProgress = NULL; }
    if (ip) idx_progress_free(ip);
    free_vm_area(vma);

    if (ix && ownsIndex) {
        if (self.cachedIdx)
            idx_free(self.cachedIdx);
        self.cachedIdx     = ix;
        self.cachedPID     = pid;
        self.cachedFilters = sig;
    }

    if (!ix) {
        if (error) *error = [self errorWithText:
            (self.cancelRequested ? @"已取消" : @"建立索引失败（内存不足？）")];
        return nil;
    }

    result.indexEntries  = (NSUInteger)idx_count(ix);
    result.indexSegments = (NSUInteger)idx_seg_count(ix);

    if (self.cancelRequested) {
        if (ownsIndex && self.cachedIdx != ix) idx_free(ix);
        result.cancelled = YES;
        result.resultsFilePath = path;
        return result;
    }

    /* 3. 扫描 */
    int depth = o.maxDepth > 0 ? o.maxDepth : 5;
    if (depth > PC_MAX_DEPTH) depth = PC_MAX_DEPTH;

    uint64_t *maxOff = (uint64_t *)calloc((size_t)depth, sizeof(uint64_t));
    int     *maxK    = (int *)calloc((size_t)depth, sizeof(int));
    if (!maxOff || !maxK) {
        free(maxOff); free(maxK);
        if (ownsIndex && self.cachedIdx != ix) idx_free(ix);
        if (error) *error = [self errorWithText:@"内存不足（参数数组）"];
        return nil;
    }
    uint64_t layer1 = o.maxOffset ? o.maxOffset : 0x1000;
    uint64_t deeper = o.maxOffsetDeep ? o.maxOffsetDeep : layer1;

    if (layer1 < 0x200)  layer1 = 0x200;
    if (deeper < 0x200)  deeper = 0x200;

    [LoggingService log:@"[指针扫描] 分层窗口: 第1层=0x%llX 其余=0x%llX",
     (unsigned long long)layer1, (unsigned long long)deeper];

    /* 尾偏移白名单：每层一组（分号分隔），组内逗号分隔 */
    int32_t tailFlat[64];
    int     tailStarts[TL_LAYER_MAX + 1];
    int     tailFlatN = 0, tailLayers = 0;

    tailStarts[0] = 0;

    if (o.tailOffsets.length > 0) {
        for (NSString *group in [o.tailOffsets componentsSeparatedByString:@";"]) {
            NSString *g = [group stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
            if (g.length == 0)
                continue;
            if (tailLayers >= TL_LAYER_MAX)
                break;

            int n = 0;
            for (NSString *piece in [g componentsSeparatedByString:@","]) {
                NSString *t = [piece stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceCharacterSet]];
                if (t.length == 0)
                    continue;
                if ([t hasPrefix:@"0x"] || [t hasPrefix:@"0X"])
                    t = [t substringFromIndex:2];
                if (tailFlatN + n >= (int)(sizeof(tailFlat) / sizeof(tailFlat[0])))
                    break;
                tailFlat[tailFlatN + n] = (int32_t)strtoll(t.UTF8String, NULL, 16);
                n++;
            }
            if (n == 0)
                continue;

            tailFlatN += n;
            tailLayers++;
            tailStarts[tailLayers] = tailFlatN;
        }
        if (tailLayers > 0) {
            [LoggingService log:@"[指针扫描] 尾偏移 %d 层, %d 个偏移", tailLayers, tailFlatN];
        }
    }

    struct fs_opts opts;
    memset(&opts, 0, sizeof(opts));
    opts.target                   = (uintptr_t)o.targetAddress;
    opts.max_depth                = depth;
    opts.min_depth                = o.minDepth;
    opts.max_chains               = o.maxChains > 0 ? (int)o.maxChains : 0;
    opts.max_off                  = maxOff;
    opts.max_off_len              = depth;
    opts.max_targets_per_node     = maxK;
    opts.max_targets_per_node_len = depth;
    if (tailLayers > 0 && tailFlatN > 0) {
        opts.tail_flat        = tailFlat;
        opts.tail_starts      = tailStarts;
        opts.tail_layer_count = tailLayers;
    }

    struct fs_progress *fp = create_fs_progress();
    if (!fp) {
        free(maxOff); free(maxK);
        if (ownsIndex && self.cachedIdx != ix) idx_free(ix);
        if (error) *error = [self errorWithText:@"内存不足（扫描进度）"];
        return nil;
    }
    @synchronized (self) { self.fsProgress = fp; }

    __block BOOL scanDone = NO;
    dispatch_async(pollQueue, ^{
        while (!scanDone) {
            uint64_t chains  = atomic_load(&fp->total_chains);
            uint64_t hits    = atomic_load(&fp->layer_hits);
            uint64_t in      = atomic_load(&fp->layer_in);
            int      phase   = atomic_load(&fp->phase);
            if (progress) {
                NSString *s;
                if (phase == FS_SCAN_PHASE_ENUM)
                    s = [NSString stringWithFormat:@"整理链路… 已找到 %llu 条",
                         (unsigned long long)chains];
                else
                    s = [NSString stringWithFormat:@"搜索指针 %llu 入 / %llu 命中 / %llu 条链",
                         (unsigned long long)in, (unsigned long long)hits,
                         (unsigned long long)chains];
                progress(0.5f + (chains > 0 ? 0.4f : 0.1f), s);
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });

    /*
     * 自动调参：一次扫不出东西时不要让人去猜参数。
     *   - 撞到库的单层内存预算（窗口太大，深层扇出爆炸）→ 缩小"其余层窗口"重试
     *   - 正常结束但 0 条链（第 1 层窗口够不到对象基址）→ 放大第 1 层窗口重试
     *   - 开了"只扫可写"且始终 0 条 → 重建索引（不限制可写）再试一次
     * 每一步都写日志，最终仍失败才报错。
     */
    struct fs_result *fr = NULL;
    int rc = FS_SCAN_FAILED;
    int rebuilt = 0;

    for (int attempt = 0; attempt < 5; attempt++) {
        for (int i = 0; i < depth; i++) {
            maxOff[i] = (i == 0) ? layer1 : deeper;
            maxK[i]   = o.maxTargetsPerNode;
        }

        uint64_t hits_before = atomic_load(&fp->layer_hits);
        uint64_t chains_before = atomic_load(&fp->total_chains);

        rc = fs_ptrscan(ix, &opts, fp, &fr);

        [LoggingService log:@"[指针扫描] 第 %d 次尝试: rc=%d 命中=%llu 条链=%llu (第1层窗口=0x%llX 其余=0x%llX)",
         attempt + 1, rc,
         (unsigned long long)(atomic_load(&fp->layer_hits) - hits_before),
         (unsigned long long)(atomic_load(&fp->total_chains) - chains_before),
         (unsigned long long)layer1, (unsigned long long)deeper];

        if (rc == FS_SCAN_FINISH && bridge_has_chains(fr))
            break;

        if (rc == FS_SCAN_FINISH) {
            uint64_t hits = atomic_load(&fp->layer_hits) - hits_before;

            if (hits > 0) {
                /* 有候选但连不到锚点：这是游戏状态问题（对象还没挂进静态结构），
                 * 放大窗口只会让精确的边被剪枝挤掉，所以到此为止。 */
                [LoggingService log:@"[指针扫描] 有 %llu 个命中但连不到锚点："
                 @"多半是对象还没挂进游戏的静态结构（进关卡/玩一会儿再扫）",
                 (unsigned long long)hits];
                break;
            }

            /* 一个候选都没有：才是第 1 层窗口太小（值在对象里的偏移比它大） */
            if (layer1 >= 0x100000)
                break;
            free_fs_result(&fr);
            fr = NULL;
            layer1 *= 16;
            [LoggingService log:@"[指针扫描] 0 命中，第 1 层窗口放大到 0x%llX 重试",
             (unsigned long long)layer1];
            continue;
        }

        /* 预算中止：多半是深层窗口太大 */
        uint64_t smaller = deeper / 4;
        if (smaller >= 0x200) {
            free_fs_result(&fr);
            fr = NULL;
            deeper = smaller;
            [LoggingService log:@"[指针扫描] 触发内存预算，其余层窗口缩小到 0x%llX 重试",
             (unsigned long long)deeper];
            continue;
        }

        /* 窗口已经很小还不行：只扫可写时拿不到锚点，重建索引去掉限制 */
        if (o.writableOnly && !rebuilt) {
            rebuilt = 1;
            [LoggingService log:@"[指针扫描] 只扫可写内存拿不到锚点，改为索引全部可读区域"];
            free_fs_result(&fr);
            fr = NULL;
            if (ownsIndex) idx_free(ix);
            ix = NULL;
            ownsIndex = 0;
            /* 放宽过滤重建：把 maxRegion 也放开，免得再被过滤掉 */
            struct vm_area *vma2 = NULL;
            if (parse_maps(pid, &vma2) != 0)
                break;

            if (!vma2)
                break;
            bridge_apply_filters(&vma2, o, 1);
            struct idx_progress *ip2 = idx_progress_create();
            if (!ip2) { free_vm_area(vma2); break; }
            struct idx *ix2 = idx_build(pid, vma2, ptr_scan_reader, NULL, o.jobs, ip2);
            idx_progress_free(ip2);
            free_vm_area(vma2);
            if (!ix2)
                break;
            ix        = ix2;
            ownsIndex = 1;
            if (self.cachedIdx)
                idx_free(self.cachedIdx);
            self.cachedIdx     = ix;
            self.cachedPID     = pid;
            self.cachedFilters = sig;
            result.indexEntries  = (NSUInteger)idx_count(ix);
            result.indexSegments = (NSUInteger)idx_seg_count(ix);
            continue;
        }
        break;
    }

    scanDone = YES;

    @synchronized (self) { self.fsProgress = NULL; }
    free_fs_progress(fp);
    free(maxOff);
    free(maxK);

    if (progress) progress(0.95f, @"导出结果…");

    /* 4. 转换成本 App 的链文本（FilterPage 直接可读） */
    NSUInteger chains = 0, groups = 0;
    NSMutableString *out = [NSMutableString string];

    if (rc == FS_SCAN_FINISH && fr) {
        for (struct pc_list *g = fr->chains; g; g = g->next) {
            if (!g->filename) continue;
            NSString *modName = [self moduleNameForPath:g->filename];
            groups++;
            for (struct oc_block *b = g->chains; b; b = b->next) {
                int used = atomic_load(&b->used);
                for (int i = 0; i < used; i++) {
                    struct offset_chain *oc = &b->oc[i];
                    int n = oc->offsets.count;
                    if (n < 1 || !oc->offsets.offset) continue;

                    [out appendFormat:@"[%@ + 0x%llX]", modName,
                     (unsigned long long)(uint32_t)oc->offsets.offset[0]];

                    for (int k = 1; k < n; k++) {
                        int32_t d = oc->offsets.offset[k];
                        if (d < 0)
                            [out appendFormat:@" -> -0x%X", (unsigned)(-d)];
                        else
                            [out appendFormat:@" -> +0x%X", (unsigned)d];
                    }
                    [out appendString:@"\n"];
                    chains++;

                    if (o.maxChains > 0 && (NSInteger)chains >= o.maxChains)
                        break;
                }
                if (o.maxChains > 0 && (NSInteger)chains >= o.maxChains)
                    break;
            }
            if (o.maxChains > 0 && (NSInteger)chains >= o.maxChains)
                break;
        }
    }

    /* 文件头写上标识 + 生成时间（FilterPage 会忽略非 “[模块 + 偏移]” 开头的行） */
    NSMutableString *withHeader = [NSMutableString string];
    [withHeader appendFormat:@"# 指针链扫描 0CA2-4AD8-8E17-C3746067D85A  %@  目标=0x%llX  %lu 条\n",
     [NSDateFormatter localizedStringFromDate:[NSDate date]
                                     dateStyle:NSDateFormatterShortStyle
                                     timeStyle:NSDateFormatterMediumStyle],
     (unsigned long long)o.targetAddress, (unsigned long)chains];
    [withHeader appendString:out];

    [withHeader writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    result.resultsFilePath = path;
    result.chainCount      = chains;
    result.groupCount      = groups;

    free_fs_result(&fr);

    /* 缓存里的那份留着下次用；只有不是缓存的那份才释放 */
    if (ownsIndex && self.cachedIdx != ix)
        idx_free(ix);

    [LoggingService log:@"[指针扫描] 完成：%lu 条链 / %lu 组，索引 %lu 槽",
     (unsigned long)chains, (unsigned long)groups, (unsigned long)result.indexEntries];

    if (rc != FS_SCAN_FINISH && !self.cancelRequested) {
        /*
         * 库在单层命中超过"可用内存的 1/4"时会中止整次扫描（保护游戏不被
         * iOS 杀掉），此时 BFS 还没走到 ENUM，所以一条链也导不出来。
         * 说清楚原因，别让人以为是"扫完但没结果"。
         */
        NSString *why = [NSString stringWithFormat:
            @"扫描被内存预算中止（层数 %d、窗口 0x%llX 在深层扇出太大）。"
            @"请减小层数或每层窗口，或用“尾偏移”限定出口偏移后再试。",
            depth, (unsigned long long)o.maxOffset];

        [LoggingService log:@"[指针扫描] 未完成：%@", why];
        if (error) *error = [self errorWithText:why];
        return nil;
    }

    return result;
}

- (void)scanWithOptions:(PtrScanOptions *)options
               progress:(void (^)(float, NSString *))progress
             completion:(void (^)(PtrScanResult *, NSError *))completion
{
    @synchronized (self) {
        if (self.scanning) {
            if (completion)
                completion(nil, [self errorWithText:@"已有扫描在进行中"]);
            return;
        }
        self.scanning        = YES;
        self.cancelRequested = NO;
    }

    NSDate *started = [NSDate date];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            PtrScanResult *result = [self runScan:options progress:progress error:&error];

            if (result) result.duration = -[started timeIntervalSinceNow];

            @synchronized (self) { self.scanning = NO; }

            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(result, error);
                });
            }
        }
    });
}

@end
