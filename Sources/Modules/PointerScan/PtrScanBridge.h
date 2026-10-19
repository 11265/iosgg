/*
 * ============================================================================
 *  指针链扫描（pointer chain scan）—— 本节代码标识
 *    ID      : 0CA2-4AD8-8E17-C3746067D85A
 *    日期时间: 2026-10-16 02:40:18
 *    引擎    : External/ptrscan/src（fast_ptrscan 源码，in-process）
 *    说明    : 区域枚举/索引/扫描/结果导出都在这里，UI 在 PointerScanPage，
 *              结果查看与两次对比在 FilterPage。
 * ============================================================================
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * 指针扫描桥接层：把 fast_ptrscan 源码接进本插件。
 *
 * 旧实现自己用 mach_vm_read_overwrite 做 BFS，本层改为调用库里的
 *     parse_maps -> 区域过滤 -> vma_image 分类 -> idx_build -> fs_ptrscan
 * 并把库输出的偏移链转换成本 App 一直在用的文本格式：
 *
 *     [<模块名> + 0x<锚点偏移>] -> +0x<偏移> -> +0x<偏移> ...
 *
 * 这正是 FilterPage 的 loadResultsFromFile: 解析、buildItemFromRoot: 建节点、
 * validateItems: 逐跳解引用读值的格式，所以 FilterPage / PointerChainResolver
 * 不需要任何改动。
 */

@interface PtrScanOptions : NSObject

/* 目标地址：要顺着指针链找到的那个值的地址 */
@property (nonatomic, assign) uint64_t targetAddress;

/* 目标进程，0 = 本进程（插件注入在游戏里，所以通常就是游戏自己） */
@property (nonatomic, assign) pid_t targetPID;

/* 层数：最大指针深度（库的 -d） */
@property (nonatomic, assign) int maxDepth;

/* 每层搜索窗口：目标下方多少字节内算候选（库的 -O） */
@property (nonatomic, assign) uint64_t maxOffset;

/*
 * 第 1 层之后各层的搜索窗口，0 = 与 maxOffset 相同。
 *
 * 为什么要分开：第 1 层要够到"对象基址到值的偏移"（例如阳光是 0x58CC），
 * 窗口小了第 1 层就没有命中；可窗口一放大，深层扇出会按 (窗口/小窗口) 的
 * 比例爆炸 —— 手机上很快撞到库的单层内存预算，整次扫描被判失败（一条都
 * 导不出来）。库的 max_off 本来就是按层给的数组，这里把它用起来：
 * 第 1 层 0x10000 + 其余层 0x1000，深层的候选数大约只剩 1/64。
 */
@property (nonatomic, assign) uint64_t maxOffsetDeep;

/* 每层每个父节点保留多少候选，0 = 不限（库的 -k） */
@property (nonatomic, assign) int maxTargetsPerNode;

/* 最短层数，0 = 不限 */
@property (nonatomic, assign) int minDepth;

/*
 * 尾偏移白名单（库的 -t）：可以只保留"以给定偏移结尾"的链。
 * 每层一组，组内用逗号分隔，组间用分号，例如 "0x58cc;0x20;0x0"。
 * 深层扫描时用它把候选压小，才能在手机上跑到 6~7 跳而不触发内存预算。
 */
@property (nonatomic, copy, nullable) NSString *tailOffsets;

/* 最多导出多少条链，0 = 不限 */
@property (nonatomic, assign) NSInteger maxChains;

/* 只索引可写内存：跳过只读区，索引小、建得快 */
@property (nonatomic, assign) BOOL writableOnly;

/* 丢弃大于该字节数的单个区域，0 = 不限（库的 --max-region） */
@property (nonatomic, assign) uint64_t maxRegion;

/* 按路径片段排除区域，例如 @[@"dyld_shared_cache"] */
@property (nonatomic, copy, nullable) NSArray<NSString *> *excludeNames;

/* 大数组落盘（库的 --low-memory），内存紧张时用 */
@property (nonatomic, assign) BOOL lowMemory;

/* 索引线程数，0 = 库自己决定 */
@property (nonatomic, assign) int jobs;

/* 边预算 / 单层命中预算，0 = 用库默认值（防止把游戏内存吃干） */
@property (nonatomic, assign) uint64_t maxEdges;
@property (nonatomic, assign) uint64_t maxHits;

@end


@interface PtrScanResult : NSObject

/* 结果文本文件（可直接交给 FilterPage 的“加载”使用） */
@property (nonatomic, copy)   NSString *resultsFilePath;

@property (nonatomic, assign) NSUInteger chainCount;
@property (nonatomic, assign) NSUInteger groupCount;
@property (nonatomic, assign) NSUInteger indexEntries;
@property (nonatomic, assign) NSUInteger indexSegments;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) BOOL cancelled;

@end


@interface PtrScanBridge : NSObject

+ (instancetype)sharedBridge;

@property (nonatomic, readonly) BOOL isScanning;

/*
 * 跑一次指针扫描。
 *   progress   后台线程约 10Hz 回调（0..1 + 中文状态）
 *   completion 结束回调；error 非空表示失败
 */
- (void)scanWithOptions:(PtrScanOptions *)options
               progress:(nullable void (^)(float progress, NSString *status))progress
             completion:(void (^)(PtrScanResult * _Nullable result,
                                  NSError * _Nullable error))completion;

- (void)stop;

/*
 * 丢掉缓存好的索引（下次扫描会重建，约 20 秒）。
 *
 * 为什么要缓存：建索引要读几百 MB 内存，在手机上约 20 秒；而被扫的那个
 * 地址（例如阳光这种"临时地址"）在这 20 秒里会变，等索引建好再扫就已经
 * 扫不到了 —— 所以正确用法是"建一次索引，然后趁地址新鲜时连续扫"。
 */
- (void)invalidateIndexCache;

/* tmp 目录里最近一次的结果文件（pointer_scan_*.txt / pointer_chain_*.txt），没有则 nil */
- (nullable NSString *)latestResultsPath;

@end

NS_ASSUME_NONNULL_END
