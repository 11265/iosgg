#import "Modules/Scanner/Scanner.h"
#import "Core/Memory/SSMemoryBridge.h"
#import "Services/LogService.h"
#import "External/lz4/lz4.h"
#import <pthread.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#include <vector>
#import "Core/Constants/NotificationNames.h"
#import <sys/sysctl.h>
#import <time.h>
#include <algorithm>
#import <unistd.h>
#import "Modules/Scanner/ScannerKernel.h"

// ── 结果写入器 ─────────────────────────────────────────────
// 不设结果条数上限：高命中搜索(搜 0 之类)的命中全部落盘，后续筛选才有完整候选集。
// 代价是结果文件可能很大（16 字节/条），所以这里如实记录写入进度与失败条数。
#define 最大回传结果数 (2000u)              // 回传给 UI 的条数（UI 只显示前 150）
#define 本地区块容量   (4096u)              // 每个 worker 的结果缓冲(条)，攒满就落盘

typedef struct {
    FILE*           fp;
    pthread_mutex_t lock;
    size_t          已存;    // 实际写入文件的条数
    size_t          总命中;  // 扫描到的全部命中
    bool            截断;    // 有命中真的没写下去（磁盘满/写错误），不是上限
} 结果写入器;

static inline void 初始化结果写入器(结果写入器* w, FILE* fp) {
    w->fp = fp;
    pthread_mutex_init(&w->lock, NULL);
    w->已存 = 0;
    w->总命中 = 0;
    w->截断 = false;
}

/// 唯一的落盘入口：所有命中都写文件，只有 fwrite 真的失败才算丢
static inline void 提交结果(结果写入器* w, const AddressValuePair* p, size_t n) {
    if (n == 0) return;
    pthread_mutex_lock(&w->lock);
    w->总命中 += n;
    size_t 写 = fwrite(p, sizeof(AddressValuePair), n, w->fp);
    w->已存 += 写;
    if (写 != n) w->截断 = true;   // 磁盘满/写错误：这一批没写完
    pthread_mutex_unlock(&w->lock);
}

// ╔══════════════════════════════════════════╗
// ║  1. 自适应参数与辅助函数                  ║
// ╚══════════════════════════════════════════╝

/// 获取设备物理内存（字节），首次调用 sysctl 后缓存
static uint64_t 获取物理内存大小(void) {
    static uint64_t cached = 0;
    if (cached == 0) {
        int mib[2] = { CTL_HW, HW_MEMSIZE };
        size_t len = sizeof(cached);
        sysctl(mib, 2, &cached, &len, NULL, 0);
    }
    return cached;
}


/// 低内存压力检测，结果缓存 500ms，避免每个 chunk 都调 sysctl
static bool 检查内存压力(size_t threshold) {
    if (threshold == 0) return false;
    static _Atomic size_t  cached_avail = 0;
    static _Atomic uint64_t last_check_ms = 0;
    
    uint64_t now_ms = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    if (now_ms - atomic_load(&last_check_ms) > 500) {
        size_t avail = 0;
        size_t len = sizeof(avail);
        sysctlbyname("hw.memsize_usable", &avail, &len, NULL, 0);
        atomic_store(&cached_avail, avail);
        atomic_store(&last_check_ms, now_ms);
    }
    size_t mem = atomic_load(&cached_avail);
    return mem > 0 && mem < threshold;
}
// ── 后台扫描：队列 / 进度 / 取消 ────────────────────────────

static dispatch_queue_t 扫描队列(void) {
    static dispatch_queue_t 队列 = NULL;
    static dispatch_once_t 一次;
    dispatch_once(&一次, ^{
        队列 = dispatch_queue_create("com.iosgg.scanner.queue", DISPATCH_QUEUE_SERIAL);
    });
    return 队列;
}

static uint64_t 单调毫秒(void) {
    struct timespec 时间;
    clock_gettime(CLOCK_MONOTONIC, &时间);
    return (uint64_t)时间.tv_sec * 1000 + (uint64_t)(时间.tv_nsec / 1000000);
}

static bool 扫描已取消(void) {
    return atomic_load([[ScannerState shared] cancelPtr]);
}

/// 每线程内存预算：单线程峰值 × 线程数 ≤ 物理内存/8，再按 CPU 核数封顶
static int 工作线程数(size_t 单线程峰值) {
    uint64_t 物理内存 = 获取物理内存大小();
    size_t 预算 = (size_t)(物理内存 / 8);
    int 按内存 = (int)(预算 / (单线程峰值 ? 单线程峰值 : 1));
    int 按核数 = (int)[[NSProcessInfo processInfo] activeProcessorCount];
    if (按内存 < 1) 按内存 = 1;
    if (按核数 < 1) 按核数 = 1;
    return 按内存 < 按核数 ? 按内存 : 按核数;
}

/// 扫描块大小：块小一点，取消和进度的粒度才细
static inline size_t 扫描块大小(void) {
    uint64_t 物理内存 = 获取物理内存大小();
    if (物理内存 <= 1ULL * 1024 * 1024 * 1024) return 1 * 1024 * 1024;
    if (物理内存 <= 2ULL * 1024 * 1024 * 1024) return 2 * 1024 * 1024;
    return 4 * 1024 * 1024;
}

static void 重置进度(size_t 总字节) {
    atomic_store([[ScannerState shared] scanBytesTotalPtr], 总字节);
    atomic_store([[ScannerState shared] scanBytesDonePtr], 0);
}

/// 进度上报（≤10Hz，post 到主线程）
static void 上报进度(size_t 新增字节) {
    ScannerState *状态 = [ScannerState shared];
    size_t 已完成 = atomic_fetch_add([状态 scanBytesDonePtr], 新增字节) + 新增字节;
    static _Atomic uint64_t 上次通知 = 0;
    uint64_t 现在 = 单调毫秒();
    uint64_t 上次 = atomic_load(&上次通知);
    if (现在 - 上次 < 100) return;
    if (!atomic_compare_exchange_strong(&上次通知, &上次, 现在)) return;
    size_t 总量 = atomic_load([状态 scanBytesTotalPtr]);
    double 比例 = 总量 ? (double)已完成 / (double)总量 : 0.0;
    if (比例 > 1.0) 比例 = 1.0;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSearchProgressNotification
                                                            object:nil
                                                          userInfo:@{@"progress": @(比例),
                                                                     @"done": @(已完成),
                                                                     @"total": @(总量)}];
    });
}

static dispatch_queue_t 工作队列(void) {
    return dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
}

/// 扫描内核的批次回调：把命中交给结果写入器
static void 批次提交(void *上下文, const AddressValuePair *项, size_t 条数) {
    提交结果((结果写入器 *)上下文, 项, 条数);
}

// ── 内部类型定义 ────────────────────────

typedef struct {
    uint64_t start;
    size_t size;
} 区域范围;
/// 一个待扫描的连续内存块
typedef struct {
    uint64_t addr;
    size_t   size;
} 扫描块;

// ── 函数原型声明 ────────────────────────

// 首次搜索
void 执行首次搜索(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size);
void 执行精确首次搜索(数值 target, 数据类型 data_type, size_t type_size);
void 执行模糊首次搜索(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size);
// 再次搜索
void 执行再次搜索(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size);
size_t 从原始数据比较(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size, FILE* result_fp);
size_t 从上次结果比较(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size, FILE* new_fp);
// 回调
void 处理搜索结果回调(size_t match_count, const char* result_path);

// ╔══════════════════════════════════════════╗
// ║  2. 内存区域收集                         ║
// ╚══════════════════════════════════════════╝

/// 遍历进程虚拟内存空间，收集所有可写区域。
/// 区域枚举由 Shared Core 统一完成，Scanner 不再直接调用 vm_region_*。
static std::vector<区域范围> 收集有效内存区域(void) {
    std::vector<区域范围> regions;
    uint64_t cursor = 0;
    SSMemoryRegionInfo info;

    while (SSMemoryNextRegion(&cursor, true, &info)) {
        if (info.startAddress >= MEMORY_RANGE_END) {
            break;
        }
        if (info.endAddress <= MEMORY_RANGE_START) {
            continue;
        }

        const uint64_t valid_start = info.startAddress < MEMORY_RANGE_START
            ? MEMORY_RANGE_START
            : info.startAddress;
        const uint64_t valid_end = info.endAddress > MEMORY_RANGE_END
            ? MEMORY_RANGE_END
            : info.endAddress;
        if (valid_end <= valid_start) {
            continue;
        }

        区域范围 region = {valid_start, (size_t)(valid_end - valid_start)};
        regions.push_back(region);
    }

    return regions;
}

// ╔══════════════════════════════════════════╗
// ║  3. 首次搜索                             ║
// ║  搜索模式二 入口 → 精确 ▸ 模糊           ║
// ╚══════════════════════════════════════════╝

/// 一次搜索的入参快照（UI 线程填好后交给扫描队列）
typedef struct {
    数值     target;
    数据类型 data_type;
    对比类型 type;
} 搜索参数;

/// 在扫描队列里真正执行一次搜索（首次或再次）
static void 执行一次搜索(搜索参数 *参数) {
    size_t type_size = 获取类型大小(参数->data_type);
    if (!global_scan_id) {
        [ScannerState shared].scanId = 生成扫描id();
        执行首次搜索(参数->target, 参数->data_type, 参数->type, type_size);
    } else {
        [LoggingService log:@"执行再次搜索"];
        执行再次搜索(参数->target, 参数->data_type, 参数->type, type_size);
    }
}

/// 搜索模式二：值搜索的对外入口
/// 立刻返回，真正的扫描在串行扫描队列里跑；根据 scanId 是否为空分发首次/再次搜索
/// 取消用 取消搜索()，进度通过 kSearchProgressNotification 上报
void 搜索模式二(数值 target, 数据类型 data_type, 对比类型 type) {
    ScannerState *状态 = [ScannerState shared];
    if (atomic_load([状态 scanningPtr])) {
        [LoggingService log:@"上一次扫描还没结束，忽略本次请求"];
        return;
    }
    
    状态.currentSearchMode = 模式二;
    状态.currentDataType = data_type;
    状态.resultTruncated = NO;   // 每次新搜索重置截断标记
    [LoggingService log:@"执行搜索模式二 - 数据类型: %d, 对比类型: %d", data_type, type];
    
    // 记录搜索参数
    if (type == 区间) {
        switch (data_type) {
            case 类型_整数:
                [LoggingService log:@"区间搜索范围: %d 到 %d", target.range_i.min, target.range_i.max];
                break;
            case 类型_长整数:
                [LoggingService log:@"区间搜索范围: %lld 到 %lld", target.range_l.min, target.range_l.max];
                break;
            case 类型_浮点:
                [LoggingService log:@"区间搜索范围: %f 到 %f", target.range_f.min, target.range_f.max];
                break;
            case 类型_双精度:
                [LoggingService log:@"区间搜索范围: %f 到 %f", target.range_d.min, target.range_d.max];
                break;
            case 类型_字节:
            case 类型_短整数:
                [LoggingService log:@"区间搜索范围: %d 到 %d", target.range_i.min & (data_type == 类型_字节 ? 0xFF : 0xFFFF), target.range_i.max & (data_type == 类型_字节 ? 0xFF : 0xFFFF)];
                break;
        }
    }
    
    // 初始化搜索结果
    if (!search_results) {
        [ScannerState shared].searchResults = (SearchResult*)malloc(sizeof(SearchResult));
        if (!search_results) {
            [LoggingService log:@"无法分配搜索结果结构体内存"];
            return;
        }
        search_results->count = 0;
        search_results->result_file_path = NULL;
    }
    
    if (!global_scanner) {
        [ScannerState shared].scanner = 创建扫描器();
        if (!global_scanner) {
            [LoggingService log:@"错误：创建扫描器失败"];
            return;
        }
    }
    
    搜索参数 *参数 = (搜索参数*)malloc(sizeof(搜索参数));
    if (!参数) {
        [LoggingService log:@"无法分配搜索参数"];
        return;
    }
    参数->target = target;
    参数->data_type = data_type;
    参数->type = type;
    
    atomic_store([状态 cancelPtr], false);
    atomic_store([状态 scanBytesDonePtr], 0);
    atomic_store([状态 scanBytesTotalPtr], 0);
    atomic_store([状态 scanningPtr], true);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kSearchStartNotification object:nil];
    
    dispatch_async(扫描队列(), ^{
        执行一次搜索(参数);
        free(参数);
        
        bool 取消 = atomic_load([状态 cancelPtr]);
        atomic_store([状态 scanningPtr], false);
        size_t 条数 = (状态.searchResults != NULL) ? 状态.searchResults->count : 0;
        
        // 首次搜索被取消：清掉 scanId，下次仍然从"首次搜索"开始，不会误进"再次搜索"
        if (取消 && 条数 == 0 &&
            (状态.searchResults == NULL || 状态.searchResults->result_file_path == NULL)) {
            if (状态.scanId != NULL) {
                free(状态.scanId);
                状态.scanId = NULL;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kSearchFinishNotification
                                                                object:nil
                                                              userInfo:@{@"cancelled": @(取消),
                                                                         @"count": @(条数)}];
        });
    });
}

void 取消搜索(void) {
    atomic_store([[ScannerState shared] cancelPtr], true);
    [LoggingService log:@"收到取消请求，正在停止扫描"];
}

bool 是否正在扫描(void) {
    return atomic_load([[ScannerState shared] scanningPtr]);
}

/// 首次搜索分发：精确走精确搜索，其他走模糊快照
void 执行首次搜索(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size) {
    if (type == 精确) {
        执行精确首次搜索(target, data_type, type_size);
    } else {
        执行模糊首次搜索(target, data_type, type, type_size);
    }
}

/// 精确首次搜索：GCD 并行遍历所有可写内存区域，逐值比较
///
/// 不设结果条数上限：内存全量读取比较，命中全部落盘。
/// 不能因为"结果满了"就跳过读取 —— 跳过的内存永远不会被检查，那是真正的漏数据。
void 执行精确首次搜索(数值 target, 数据类型 data_type, size_t type_size) {
    [LoggingService log:@"执行精确搜索"];
    char* result_path = 创建临时文件();
    if (!result_path) {
        [LoggingService log:@"无法创建结果文件"];
        return;
    }
    
    FILE* result_fp = fopen(result_path, "wb");
    if (!result_fp) {
        free(result_path);
        [LoggingService log:@"无法打开结果文件"];
        return;
    }
    
    结果写入器* writer = (结果写入器*)malloc(sizeof(结果写入器));
    if (!writer) {
        fclose(result_fp);
        删除临时文件(result_path);
        free(result_path);
        [LoggingService log:@"无法分配结果写入器"];
        return;
    }
    初始化结果写入器(writer, result_fp);
    
    std::vector<区域范围> 区域表 = 收集有效内存区域();
    
    // 展开成块列表：任务粒度是"块"，不是"区域"
    const size_t 块大小 = 扫描块大小();
    std::vector<扫描块>* 块表 = new std::vector<扫描块>();
    size_t 总字节 = 0;
    for (size_t r = 0; r < 区域表.size(); r++) {
        for (size_t 偏移 = 0; 偏移 < 区域表[r].size; 偏移 += 块大小) {
            size_t 本块 = (偏移 + 块大小 > 区域表[r].size) ? (区域表[r].size - 偏移) : 块大小;
            扫描块 项 = { 区域表[r].start + 偏移, 本块 };
            块表->push_back(项);
            总字节 += 本块;
        }
    }
    重置进度(总字节);
    
    const int 线程数 = 工作线程数(块大小 * 2);
    [LoggingService log:@"精确搜索：%zu 块 / %zu 区域 / %.1fMB，%d 线程，块 %zuKB",
        块表->size(), 区域表.size(), (double)总字节 / 1048576.0, 线程数, 块大小 / 1024];
    
    __block atomic_size_t 下一个 = 0;
    __block atomic_size_t 读失败块 = 0;
    __block atomic_size_t 读失败字节 = 0;
    __block atomic_size_t 读不全字节 = 0;
    dispatch_apply(线程数, 工作队列(), ^(size_t 序号) {
        uint8_t* 缓冲 = (uint8_t*)malloc(块大小);
        AddressValuePair* 暂存 = (AddressValuePair*)malloc(sizeof(AddressValuePair) * 本地区块容量);
        if (!缓冲 || !暂存) {
            free(缓冲);
            free(暂存);
            [LoggingService log:@"线程 %zu 缓冲区分配失败", 序号];
            return;
        }
        
        for (;;) {
            if (扫描已取消()) break;
            size_t i = atomic_fetch_add(&下一个, 1);
            if (i >= 块表->size()) break;
            
            const 扫描块 块 = (*块表)[i];
            size_t 读到 = 0;
            const bool 读取成功 = SSMemoryRead(块.addr, 缓冲, 块.size, &读到);
            
            // 部分读取时已读到的前缀照样扫，不能整块丢掉
            size_t 可扫 = 0;
            if (读取成功 && 读到 == 块.size) {
                可扫 = 块.size;
            } else if (读到 > 0) {
                可扫 = 读到;
            }
            if (可扫 > 0) {
                扫描块_单值(缓冲, 可扫, 块.addr, data_type, 精确, &target,
                            暂存, 本地区块容量, 批次提交, writer);
                if (可扫 < 块.size) {
                    atomic_fetch_add(&读不全字节, 块.size - 可扫);   // 尾部没读到
                }
            } else {
                atomic_fetch_add(&读失败块, 1);                      // 整块没读到
                atomic_fetch_add(&读失败字节, 块.size);
            }
            上报进度(块.size);
        }
        
        free(缓冲);
        free(暂存);
    });
    
    delete 块表;
    
    size_t match_count = writer->已存;
    size_t 总命中 = writer->总命中;
    bool 结果截断 = writer->截断;
    bool 被取消 = 扫描已取消();
    
    fclose(result_fp);
    pthread_mutex_destroy(&writer->lock);
    free(writer);
    
    if (被取消) {
        删除临时文件(result_path);
        free(result_path);
        [LoggingService log:@"精确搜索已取消（命中 %zu 条未采用），保留上一轮结果集", 总命中];
        return;
    }
    
    if (search_results->result_file_path) {
        删除临时文件(search_results->result_file_path);   // 旧结果集不再需要
        free(search_results->result_file_path);
    }
    search_results->result_file_path = result_path;
    search_results->count = match_count;
    [ScannerState shared].resultTruncated = 结果截断;
    struct stat 结果文件;
    double 文件MB = (stat(result_path, &结果文件) == 0) ? (double)结果文件.st_size / 1048576.0 : 0.0;
    [LoggingService log:@"精确搜索完成：命中 %zu 条，写入 %zu 条%s，结果文件 %.1fMB",
        总命中, match_count, 结果截断 ? "（有命中写入失败）" : "", 文件MB];
    if (atomic_load(&读失败块) > 0 || atomic_load(&读不全字节) > 0) {
        [LoggingService log:@"⚠️ 有内存没读到：整块失败 %zu 块 / %zu MB，部分读取缺失 %zu MB",
            atomic_load(&读失败块), atomic_load(&读失败字节) / 1048576,
            atomic_load(&读不全字节) / 1048576];
    }
    
    处理搜索结果回调(match_count, result_path);
}

/// 往快照表追加一条（调用方持有 dump_mutex）
static bool 追加内存条目(MemoryEntry 条目) {
    if (global_memory_count >= global_memory_capacity) {
        size_t 新容量 = global_memory_capacity ? global_memory_capacity * 2 : 4096;
        MemoryEntry* 新表 = (MemoryEntry*)realloc(global_memory, 新容量 * sizeof(MemoryEntry));
        if (!新表) return false;
        [ScannerState shared].memory = 新表;
        [ScannerState shared].memoryCapacity = 新容量;
    }
    global_memory[global_memory_count++] = 条目;
    return true;
}

/// 模糊首次搜索：LZ4 压缩快照全量可写内存，供后续变化搜索对比
/// 首次仅建立快照不返回结果，等待 执行再次搜索 触发对比
void 执行模糊首次搜索(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size) {
    // 1. 准备全局转储文件（单一文件替代大量小文件）
    if (global_dump_file_path) {
        删除临时文件(global_dump_file_path);
        free(global_dump_file_path);
    }
    [ScannerState shared].dumpFilePath = 创建临时文件();
    if (!global_dump_file_path) {
        [LoggingService log:@"无法创建全局转储文件"];
        return;
    }
    
    FILE* dump_fp = fopen(global_dump_file_path, "wb");
    if (!dump_fp) {
        free(global_dump_file_path);
        [ScannerState shared].dumpFilePath = NULL;
        [LoggingService log:@"无法打开全局转储文件"];
        return;
    }
    
    // 2. 初始化全局内存条目数组
    if (global_memory) free(global_memory);
    [ScannerState shared].memoryCapacity = 4096;
    [ScannerState shared].memory = (MemoryEntry*)malloc(sizeof(MemoryEntry) * global_memory_capacity);
    [ScannerState shared].memoryCount = 0;
    
    pthread_mutex_t *dump_mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    pthread_mutex_init(dump_mutex, NULL);
    
    std::vector<区域范围> 区域表 = 收集有效内存区域();
    
    const size_t 块大小 = 扫描块大小();
    std::vector<扫描块>* 块表 = new std::vector<扫描块>();
    size_t 总字节 = 0;
    for (size_t r = 0; r < 区域表.size(); r++) {
        for (size_t 偏移 = 0; 偏移 < 区域表[r].size; 偏移 += 块大小) {
            size_t 本块 = (偏移 + 块大小 > 区域表[r].size) ? (区域表[r].size - 偏移) : 块大小;
            扫描块 项 = { 区域表[r].start + 偏移, 本块 };
            块表->push_back(项);
            总字节 += 本块;
        }
    }
    重置进度(总字节);
    
    const int 压缩上限 = LZ4_compressBound((int)块大小);
    const int 线程数 = 工作线程数(块大小 + (size_t)压缩上限);
    const size_t 压力阈值 = (块大小 <= 2 * 1024 * 1024)
        ? (size_t)(获取物理内存大小() * 0.15) : 0;
    
    [LoggingService log:@"模糊首次搜索：%zu 块 / %zu 区域 / %.1fMB，%d 线程",
        块表->size(), 区域表.size(), (double)总字节 / 1048576.0, 线程数];
    
    __block atomic_size_t 下一个 = 0;
    __block atomic_size_t 覆盖字节 = 0;
    __block atomic_size_t 跳过块数 = 0;
    __block atomic_size_t 跳过字节 = 0;
    
    dispatch_apply(线程数, 工作队列(), ^(size_t 序号) {
        uint8_t* 读缓冲 = (uint8_t*)malloc(块大小);
        char* 压缓冲 = (char*)malloc((size_t)压缩上限);
        if (!读缓冲) {
            [LoggingService log:@"线程 %zu 读缓冲分配失败", 序号];
            free(压缓冲);
            return;
        }
        
        for (;;) {
            if (扫描已取消()) break;
            size_t i = atomic_fetch_add(&下一个, 1);
            if (i >= 块表->size()) break;
            
            const 扫描块 块 = (*块表)[i];
            
            // 内存吃紧时让出 CPU（内部有 500ms 缓存，代价可忽略）
            if (检查内存压力(压力阈值)) usleep(50000);
            
            size_t 读到 = 0;
            const bool 读取成功 = SSMemoryRead(块.addr, 读缓冲, 块.size, &读到);
            size_t 可存 = 0;
            if (读取成功 && 读到 == 块.size) {
                可存 = 块.size;
            } else if (读到 > 0) {
                可存 = 读到;   // 部分读取：已读到的前缀照样进快照
            }
            
            if (可存 == 0) {
                atomic_fetch_add(&跳过块数, 1);
                atomic_fetch_add(&跳过字节, 块.size);
                上报进度(块.size);
                continue;
            }
            
            int 压缩后 = 压缓冲
                ? LZ4_compress_default((const char*)读缓冲, 压缓冲, (int)可存, 压缩上限) : 0;
            
            bool 已存 = false;
            pthread_mutex_lock(dump_mutex);
            long 文件偏移 = ftell(dump_fp);
            if (压缩后 > 0) {
                if (fwrite(压缓冲, 1, (size_t)压缩后, dump_fp) == (size_t)压缩后) {
                    MemoryEntry 条目 = {};
                    条目.address = 块.addr;
                    条目.file_offset = (uint64_t)文件偏移;
                    条目.compressed_size = (size_t)压缩后;
                    条目.uncompressed_size = 可存;
                    条目.is_first = true;
                    条目.is_compressed = true;
                    已存 = 追加内存条目(条目);
                }
            } else if (fwrite(读缓冲, 1, 可存, dump_fp) == 可存) {
                MemoryEntry 条目 = {};
                条目.address = 块.addr;
                条目.file_offset = (uint64_t)文件偏移;
                条目.compressed_size = 可存;
                条目.uncompressed_size = 可存;
                条目.is_first = true;
                条目.is_compressed = false;
                已存 = 追加内存条目(条目);
            }
            pthread_mutex_unlock(dump_mutex);
            
            if (已存) {
                atomic_fetch_add(&覆盖字节, 可存);
                if (可存 < 块.size) {
                    atomic_fetch_add(&跳过字节, 块.size - 可存);   // 部分读取的尾部没进快照
                }
            } else {
                atomic_fetch_add(&跳过块数, 1);
                atomic_fetch_add(&跳过字节, 块.size);
            }
            上报进度(块.size);
        }
        
        free(读缓冲);
        free(压缓冲);
    });
    
    delete 块表;
    
    bool 被取消 = 扫描已取消();
    fclose(dump_fp);
    pthread_mutex_destroy(dump_mutex);
    free(dump_mutex);
    
    if (被取消) {
        [ScannerState shared].memoryCount = 0;
        删除临时文件(global_dump_file_path);
        free(global_dump_file_path);
        [ScannerState shared].dumpFilePath = NULL;
        [LoggingService log:@"模糊首次搜索已取消，快照丢弃"];
        return;
    }
    
    [LoggingService log:@"快照完成：覆盖 %zu MB / %zu 块，跳过 %zu 块 / %zu MB",
        atomic_load(&覆盖字节) / 1048576, global_memory_count,
        atomic_load(&跳过块数), atomic_load(&跳过字节) / 1048576];
    
    // 初始化结果集（模糊首次结果为空，等待下一次搜索）
    if (search_results->result_file_path) {
        删除临时文件(search_results->result_file_path);
        free(search_results->result_file_path);
        search_results->result_file_path = NULL;
    }
    search_results->count = 0;
    
    处理搜索结果回调(0, NULL);
}

// ╔══════════════════════════════════════════╗
// ║  4. 再次搜索                             ║
// ║  过滤模式(从结果筛选) ▸ 快照模式(全量对比) ║
// ╚══════════════════════════════════════════╝

/// 再次搜索：优先走过滤模式（从上次结果筛选），无结果时走快照模式
/// 再次搜索：优先走过滤模式（从上次结果筛选），无结果时走快照模式
void 执行再次搜索(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size) {
    char* new_result_path = 创建临时文件();
    if (!new_result_path) {
        [LoggingService log:@"无法创建新的结果文件"];
        return;
    }
    
    FILE* new_fp = fopen(new_result_path, "wb");
    if (!new_fp) {
        free(new_result_path);
        [LoggingService log:@"无法打开新的结果文件"];
        return;
    }
    
    size_t match_count = 0;
    
    // 1. 有上一轮结果集：在结果集上筛选（最省）
    // 2. 结果集为空但有快照：从全量快照对比
    if (search_results && search_results->count > 0 && search_results->result_file_path) {
        [LoggingService log:@"执行再次搜索 - 基于已有结果集 (%zu 个)", search_results->count];
        match_count = 从上次结果比较(target, data_type, type, type_size, new_fp);
    } else if (global_memory_count > 0) {
        [LoggingService log:@"执行再次搜索 - 基于内存快照 (%zu 个块)", global_memory_count];
        match_count = 从原始数据比较(target, data_type, type, type_size, new_fp);
    } else {
        [LoggingService log:@"错误：没有可用的搜索基础（既无结果集也无快照）"];
    }
    
    fclose(new_fp);
    
    if (扫描已取消()) {
        删除临时文件(new_result_path);
        free(new_result_path);
        [LoggingService log:@"再次搜索已取消，保留上一轮结果集"];
        return;
    }
    
    if (search_results->result_file_path) {
        删除临时文件(search_results->result_file_path);   // 旧结果集不再需要
        free(search_results->result_file_path);
    }
    search_results->result_file_path = new_result_path;
    search_results->count = match_count;
    
    [LoggingService log:@"再次搜索完成，找到 %zu 个匹配结果", match_count];
    
    处理搜索结果回调(match_count, new_result_path);
}

/// 快照模式再次搜索：mmap 旧 dump → GCD 并行逐块解压/对比 → 增量写新 dump
/// 已变化块重新 LZ4 压缩，未变化块直接复用旧压缩数据
/// 快照文件里废弃数据超过一半时重写一份紧凑的（只在扫描结束后、单线程调用）
static bool 压缩快照文件(void) {
    if (!global_dump_file_path || global_memory_count == 0) return false;
    
    char* 新路径 = 创建临时文件();
    if (!新路径) return false;
    FILE* 新文件 = fopen(新路径, "wb");
    if (!新文件) {
        free(新路径);
        return false;
    }
    int 源 = open(global_dump_file_path, O_RDONLY);
    if (源 < 0) {
        fclose(新文件);
        删除临时文件(新路径);
        free(新路径);
        return false;
    }
    
    bool 成功 = true;
    uint64_t 新偏移 = 0;
    for (size_t i = 0; i < global_memory_count && 成功; i++) {
        MemoryEntry* 条目 = &global_memory[i];
        const size_t 长度 = 条目->compressed_size;
        void* 缓冲 = malloc(长度 ? 长度 : 1);
        if (!缓冲) { 成功 = false; break; }
        ssize_t 读到 = pread(源, 缓冲, 长度, (off_t)条目->file_offset);
        if (读到 != (ssize_t)长度 || fwrite(缓冲, 1, 长度, 新文件) != 长度) {
            成功 = false;
        } else {
            条目->file_offset = 新偏移;
            新偏移 += 长度;
        }
        free(缓冲);
    }
    
    fclose(新文件);
    close(源);
    
    if (!成功) {
        删除临时文件(新路径);
        free(新路径);
        return false;
    }
    
    删除临时文件(global_dump_file_path);
    free(global_dump_file_path);
    [ScannerState shared].dumpFilePath = 新路径;
    [LoggingService log:@"快照整理完成：%zu 块 / %.1fMB", global_memory_count, (double)新偏移 / 1048576.0];
    return true;
}

/// 快照模式再次搜索：逐块对比当前内存与快照。
/// 快照文件原地更新（压缩后放得下就覆盖，放不下就追加到文件尾），不再整份重写。
size_t 从原始数据比较(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size, FILE* result_fp) {
    [LoggingService log:@"从原始数据进行比较 - 原地更新快照"];
    
    if (!global_dump_file_path) {
        [LoggingService log:@"错误：没有全局转储文件"];
        return 0;
    }
    
    int dump_fd = open(global_dump_file_path, O_RDWR);
    if (dump_fd < 0) {
        [LoggingService log:@"无法以读写方式打开全局转储文件"];
        return 0;
    }
    
    struct stat st;
    if (fstat(dump_fd, &st) != 0 || st.st_size == 0) {
        close(dump_fd);
        return 0;
    }
    size_t file_size = (size_t)st.st_size;
    
    void* mapped_data = mmap(NULL, file_size, PROT_READ, MAP_PRIVATE, dump_fd, 0);
    if (mapped_data == MAP_FAILED) {
        [LoggingService log:@"mmap 失败"];
        close(dump_fd);
        return 0;
    }
    
    结果写入器* writer = (结果写入器*)malloc(sizeof(结果写入器));
    if (!writer) {
        munmap(mapped_data, file_size);
        close(dump_fd);
        return 0;
    }
    初始化结果写入器(writer, result_fp);
    
    pthread_mutex_t *dump_mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    pthread_mutex_init(dump_mutex, NULL);
    
    size_t 最大块 = 0;
    size_t 总字节 = 0;
    for (size_t i = 0; i < global_memory_count; i++) {
        if (global_memory[i].uncompressed_size > 最大块) 最大块 = global_memory[i].uncompressed_size;
        总字节 += global_memory[i].uncompressed_size;
    }
    if (最大块 == 0) 最大块 = 扫描块大小();
    
    重置进度(总字节);
    
    const int 压缩上限 = LZ4_compressBound((int)最大块);
    const int 线程数 = 工作线程数(最大块 * 3);   // 旧值 + 当前值 + 压缩缓冲
    [LoggingService log:@"快照再次搜索：%zu 块 / %.1fMB，%d 线程，快照 %.1fMB",
        global_memory_count, (double)总字节 / 1048576.0, 线程数, (double)file_size / 1048576.0];
    
    __block atomic_size_t 下一个 = 0;
    __block atomic_size_t 写失败块 = 0;
    __block atomic_size_t 追加字节 = 0;
    __block off_t 文件末尾 = (off_t)file_size;   // 只在持有 dump_mutex 时修改
    
    dispatch_apply(线程数, 工作队列(), ^(size_t 序号) {
        uint8_t* 旧值 = (uint8_t*)malloc(最大块);
        uint8_t* 当前 = (uint8_t*)malloc(最大块);
        char* 压缩缓冲 = (char*)malloc((size_t)压缩上限);
        AddressValuePair* 暂存 = (AddressValuePair*)malloc(sizeof(AddressValuePair) * 本地区块容量);
        
        if (!旧值 || !当前 || !暂存) {
            [LoggingService log:@"线程 %zu 缓冲区分配失败", 序号];
            free(旧值); free(当前); free(压缩缓冲); free(暂存);
            return;
        }
        
        for (;;) {
            if (扫描已取消()) break;
            size_t i = atomic_fetch_add(&下一个, 1);
            if (i >= global_memory_count) break;
            
            MemoryEntry* 条目 = &global_memory[i];
            const size_t 块长 = 条目->uncompressed_size;
            if (块长 == 0 || 块长 > 最大块) {
                上报进度(块长);
                continue;
            }
            // 旧偏移越界/解压失败：这块保持原状（快照是原地更新的，旧数据仍然有效）
            if (条目->file_offset + 条目->compressed_size > file_size) {
                上报进度(块长);
                continue;
            }
            
            const char* 旧文件 = (const char*)mapped_data + 条目->file_offset;
            if (条目->is_compressed) {
                if (LZ4_decompress_safe(旧文件, (char*)旧值,
                        (int)条目->compressed_size, (int)块长) <= 0) {
                    上报进度(块长);
                    continue;
                }
            } else {
                memcpy(旧值, 旧文件, 块长);
            }
            
            size_t 读到 = 0;
            if (!SSMemoryRead(条目->address, 当前, 块长, &读到) || 读到 != 块长) {
                上报进度(块长);
                continue;
            }
            
            // 块整体没变时，"变化/增加/减少"不可能命中，直接跳过逐值比较
            bool 变了 = memcmp(当前, 旧值, 块长) != 0;
            bool 跳过比较 = !变了 && (type == 变化 || type == 增加了 || type == 减少了
                                      || type == 增加了多少 || type == 减少了多少);
            if (!跳过比较) {
                扫描块_双值(当前, 旧值, 块长, 条目->address, data_type, type, &target,
                            暂存, 本地区块容量, 批次提交, writer);
            }
            
            if (变了) {
                int 压缩后 = 压缩缓冲
                    ? LZ4_compress_default((const char*)当前, 压缩缓冲, (int)块长, 压缩上限) : 0;
                bool 已存 = false;
                
                if (压缩后 > 0) {
                    if ((size_t)压缩后 <= 条目->compressed_size) {
                        // 原地覆盖：不占新空间
                        if (pwrite(dump_fd, 压缩缓冲, (size_t)压缩后,
                                   (off_t)条目->file_offset) == 压缩后) {
                            条目->compressed_size = (size_t)压缩后;
                            条目->is_compressed = true;
                            已存 = true;
                        }
                    } else {
                        pthread_mutex_lock(dump_mutex);
                        off_t 位置 = 文件末尾;
                        文件末尾 += 压缩后;
                        pthread_mutex_unlock(dump_mutex);
                        if (pwrite(dump_fd, 压缩缓冲, (size_t)压缩后, 位置) == 压缩后) {
                            条目->file_offset = (uint64_t)位置;
                            条目->compressed_size = (size_t)压缩后;
                            条目->is_compressed = true;
                            atomic_fetch_add(&追加字节, (size_t)压缩后);
                            已存 = true;
                        }
                    }
                } else if (块长 <= 条目->compressed_size) {
                    if (pwrite(dump_fd, 当前, 块长, (off_t)条目->file_offset) == (ssize_t)块长) {
                        条目->compressed_size = 块长;
                        条目->is_compressed = false;
                        已存 = true;
                    }
                } else {
                    pthread_mutex_lock(dump_mutex);
                    off_t 位置 = 文件末尾;
                    文件末尾 += (off_t)块长;
                    pthread_mutex_unlock(dump_mutex);
                    if (pwrite(dump_fd, 当前, 块长, 位置) == (ssize_t)块长) {
                        条目->file_offset = (uint64_t)位置;
                        条目->compressed_size = 块长;
                        条目->is_compressed = false;
                        atomic_fetch_add(&追加字节, 块长);
                        已存 = true;
                    }
                }
                
                if (!已存) {
                    条目->address = 0;   // 写坏了：这块作废，避免下一轮读到半截数据
                    atomic_fetch_add(&写失败块, 1);
                }
            }
            
            上报进度(块长);
        }
        
        free(旧值);
        free(当前);
        free(压缩缓冲);
        free(暂存);
    });
    
    munmap(mapped_data, file_size);
    close(dump_fd);
    pthread_mutex_destroy(dump_mutex);
    free(dump_mutex);
    
    // 剔除写坏的块
    size_t 有效块 = 0;
    size_t 有效字节 = 0;
    for (size_t i = 0; i < global_memory_count; i++) {
        if (global_memory[i].address == 0) continue;
        if (有效块 != i) global_memory[有效块] = global_memory[i];
        有效字节 += global_memory[有效块].compressed_size;
        有效块++;
    }
    [ScannerState shared].memoryCount = 有效块;
    
    size_t match_count = writer->已存;
    size_t 总命中 = writer->总命中;
    bool 结果截断 = writer->截断;
    pthread_mutex_destroy(&writer->lock);
    free(writer);
    
    if (扫描已取消()) {
        [LoggingService log:@"快照对比已取消（命中 %zu 条未采用；快照已被部分更新）", 总命中];
        return 0;
    }
    
    // 垃圾（被覆盖/追加后废弃的旧数据）超过一半时整理一次
    size_t 当前大小 = (size_t)文件末尾;
    if (有效字节 > 0 && 当前大小 > 有效字节 * 3 / 2 + 16 * 1024 * 1024) {
        [LoggingService log:@"快照整理：%.1fMB → 约 %.1fMB",
            (double)当前大小 / 1048576.0, (double)有效字节 / 1048576.0];
        压缩快照文件();
    }
    
    if (atomic_load(&写失败块) > 0) {
        [LoggingService log:@"快照对比：%zu 块写入失败已作废，%zu 块追加 %.1fMB",
            atomic_load(&写失败块), global_memory_count, (double)atomic_load(&追加字节) / 1048576.0];
    }
    
    [ScannerState shared].resultTruncated = 结果截断;
    [LoggingService log:@"从原始数据比较完成：命中 %zu 条，写入 %zu 条%s", 总命中, match_count,
        结果截断 ? "（有命中写入失败）" : ""];
    
    return match_count;
}
/// 过滤模式再次搜索：候选按地址排序后按 4KB 页批量读取，一页只做一次 Shared Core 读取。
/// 候选按 6.5 万一批处理，内存占用有上界（约 1MB/批）。
size_t 从上次结果比较(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size, FILE* new_fp) {
    [LoggingService log:@"从上一次结果进行比较（页级批读）"];
    size_t match_count = 0;
    
    if (!search_results->result_file_path) {
        [LoggingService log:@"没有上一次的搜索结果"];
        return 0;
    }
    
    FILE* old_fp = fopen(search_results->result_file_path, "rb");
    if (!old_fp) {
        [LoggingService log:@"无法打开上一次结果文件"];
        return 0;
    }
    
    struct stat 文件信息;
    size_t 总量 = 0;
    if (stat(search_results->result_file_path, &文件信息) == 0) {
        总量 = (size_t)文件信息.st_size;
    }
    重置进度(总量);
    
    const size_t 批条数 = 65536;
    std::vector<AddressValuePair>* 批 = new std::vector<AddressValuePair>();
    批->reserve(批条数);
    
    size_t 符合条数 = 0;
    size_t 页读次数 = 0;
    size_t 补读次数 = 0;
    bool 截断 = false;
    bool 被取消 = false;
    
    uint8_t 页[4096 + 8];
    
    for (;;) {
        if (扫描已取消()) { 被取消 = true; break; }
        
        批->clear();
        AddressValuePair 项;
        while (批->size() < 批条数 && fread(&项, sizeof(AddressValuePair), 1, old_fp) == 1) {
            批->push_back(项);
        }
        if (批->empty()) break;
        
        // 按地址排序：同一页的候选集中在一起，一页只需读一次
        std::sort(批->begin(), 批->end(), [](const AddressValuePair& a, const AddressValuePair& b) {
            return a.address < b.address;
        });
        
        size_t i = 0;
        while (i < 批->size()) {
            const uint64_t 页基址 = (*批)[i].address & ~(uint64_t)0xFFF;
            size_t j = i + 1;
            while (j < 批->size() && ((*批)[j].address & ~(uint64_t)0xFFF) == 页基址) j++;
            
            // 先多读 8 字节（覆盖跨页的值），失败再退回整页
            size_t 可用 = 0;
            size_t 读到 = 0;
            if (SSMemoryRead(页基址, 页, sizeof(页), &读到)) {
                可用 = 读到;
            } else if (SSMemoryRead(页基址, 页, 4096, &读到)) {
                可用 = 读到;
            }
            页读次数++;
            
            for (size_t k = i; k < j; k++) {
                const AddressValuePair& 旧 = (*批)[k];
                if ((旧.address % type_size) != 0) continue;   // 跳过未对齐的地址
                
                uint8_t 单值[8];
                const uint8_t* 当前 = NULL;
                const size_t 页内偏移 = (size_t)(旧.address - 页基址);
                
                if (可用 >= 页内偏移 + type_size) {
                    当前 = 页 + 页内偏移;
                } else {
                    size_t 小 = 0;
                    if (!SSMemoryRead(旧.address, 单值, type_size, &小)
                        || 小 != type_size) {
                        continue;
                    }
                    当前 = 单值;
                    补读次数++;
                }
                
                if (!比较值(当前, 旧.bytes, &target, data_type, type)) continue;
                
                符合条数++;
                AddressValuePair 新 = {};
                新.address = 旧.address;
                memcpy(新.bytes, 当前, type_size);
                if (fwrite(&新, sizeof(AddressValuePair), 1, new_fp) == 1) {
                    match_count++;
                } else {
                    截断 = true;   // 磁盘满/写错误
                }
            }
            
            i = j;
        }
        
        上报进度(批->size() * sizeof(AddressValuePair));
    }
    
    delete 批;
    fclose(old_fp);
    
    if (被取消) {
        [LoggingService log:@"结果集筛选被取消（已处理 %zu 个候选）", 符合条数];
    }
    [ScannerState shared].resultTruncated = 截断;
    [LoggingService log:@"结果集筛选完成：命中 %zu 条，写入 %zu 条%s（页读 %zu / 补读 %zu）",
        符合条数, match_count,
        截断 ? "（有命中写入失败）" : "", 页读次数, 补读次数];
    return match_count;
}
/// match_count=0 时仅通知 UI，不清除快照
void 处理搜索结果回调(size_t match_count, const char* result_path) {
    if (!search_callback) return;
    
    if (match_count == 0) {
        // 当搜索结果为0时，仅通知UI更新，不自动清理
        // 模糊搜索（首次）结果也为0，但此时不应清理，否则会丢失快照
        [LoggingService log:@"搜索结果为0 (或是模糊首次搜索)，通知UI更新"];
        dispatch_async(dispatch_get_main_queue(), ^{
            search_callback(NULL, 0, 0, 当前数据类型);
        });
        return;
    }
    
    // 只把前 最大回传结果数 条地址交给 UI：
    // UI 只显示前 150 条，没必要为几百万条结果在主线程上逐个装箱 NSNumber。
    size_t 回传条数 = (match_count < (size_t)最大回传结果数) ? match_count : (size_t)最大回传结果数;
    uint64_t* callback_results = (uint64_t*)malloc(回传条数 * sizeof(uint64_t));
    if (!callback_results) {
        [LoggingService log:@"搜索回调缓冲区分配失败(条数: %zu)", 回传条数];
        return;
    }
    
    FILE* read_fp = result_path ? fopen(result_path, "rb") : NULL;
    if (!read_fp) {
        [LoggingService log:@"无法打开结果文件，跳过回调"];
        free(callback_results);
        return;
    }
    
    size_t index = 0;
    AddressValuePair pair;
    while (index < 回传条数 && fread(&pair, sizeof(AddressValuePair), 1, read_fp) == 1) {
        callback_results[index++] = pair.address;
    }
    fclose(read_fp);
    
    size_t 总命中 = match_count;
    dispatch_async(dispatch_get_main_queue(), ^{
        [LoggingService log:@"准备调用搜索回调 - 回传 %zu / 命中 %zu", index, 总命中];
        search_callback(callback_results, index, 总命中, 当前数据类型);
        free(callback_results);
    });
}
