#import "Services/Scanner/Scanner.h"
#import "Services/LogService.h"
#import "External/lz4/lz4.h"
#import <pthread.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#include <vector>
#import "Constants/NotificationNames.h"
#import <sys/sysctl.h>

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

/// 根据设备内存返回最优块大小
static inline size_t 低内存自适应块大小(void) {
    uint64_t physMem = 获取物理内存大小();
    // 1GB 以下设备：1MB 块，最大限度降低峰值
    if (physMem <= 1ULL * 1024 * 1024 * 1024)        return 1 * 1024 * 1024;
    // 2GB 设备：4MB 块
    if (physMem <= 2ULL * 1024 * 1024 * 1024)        return 4 * 1024 * 1024;
    // 3GB+：保持原有 16MB
    return 16 * 1024 * 1024;
}

/// 根据设备内存返回最大并发数
static inline int 低内存自适应并发数(void) {
    uint64_t physMem = 获取物理内存大小();
    if (physMem <= 1ULL * 1024 * 1024 * 1024)        return 1;   // 串行，杜绝内存峰值叠加
    if (physMem <= 2ULL * 1024 * 1024 * 1024)        return 2;
    return 0;  // 0 表示不限制（GCD 自行调度）
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

// ── 内部类型定义 ────────────────────────

typedef struct {
    vm_address_t start;
    size_t size;
} 区域范围;

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

/// 遍历进程虚拟内存空间，收集所有具备 VM_PROT_WRITE 权限的区域
static std::vector<区域范围> 收集有效内存区域(void) {
    std::vector<区域范围> regions;
    mach_port_t task = mach_task_self();
    vm_address_t address = 0;

    while (true) {
        vm_size_t size = 0;
        natural_t depth = 0;
        vm_region_submap_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = vm_region_recurse_64(task, &address, &size, &depth, (vm_region_info_t)&info, &count);

        if (kr != KERN_SUCCESS) {
            if (kr == KERN_INVALID_ADDRESS) {
                break;
            }
            [LoggingService log:@"vm_region_recurse_64 失败，错误代码: %d", kr];
            if (size == 0) {
                break;
            }
            address += size;
            continue;
        }

        if (address >= MEMORY_RANGE_END) {
            break;
        }
        if (address + size <= MEMORY_RANGE_START) {
            address += size;
            continue;
        }

        vm_address_t valid_start = address < MEMORY_RANGE_START ? MEMORY_RANGE_START : address;
        vm_address_t valid_end = (address + size) > MEMORY_RANGE_END ? MEMORY_RANGE_END : (address + size);
        size_t adjusted_size = valid_end - valid_start;

        if (是有效内存区域(info) && adjusted_size > 0) {
            区域范围 region = {valid_start, adjusted_size};
            regions.push_back(region);
        }

        address += size;
    }

    return regions;
}

// ╔══════════════════════════════════════════╗
// ║  3. 首次搜索                             ║
// ║  搜索模式二 入口 → 精确 ▸ 模糊           ║
// ╚══════════════════════════════════════════╝

/// 搜索模式二：值搜索的对外入口
/// 根据 scanId 是否为空，自动分发到首次搜索或再次搜索
void 搜索模式二(数值 target, 数据类型 data_type, 对比类型 type) {
    [ScannerState shared].currentSearchMode = 模式二;
    [ScannerState shared].currentDataType = data_type;
    [LoggingService log:@"执行搜索模式二 - 数据类型: %d, 对比类型: %d", data_type, type];
    
    // 记录搜索参数
    if (type == 区间) {
        // 记录搜索范围
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
            case 类型_指针:
                [LoggingService log:@"区间搜索范围: 0x%llX 到 0x%llX", (uint64_t)target.range_l.min, (uint64_t)target.range_l.max];
                break;
        }
    }
    
    // 获取数据类型大小
    size_t type_size = 获取类型大小(data_type);
    
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

    // 第一次搜索
    if (!global_scan_id) {
        [LoggingService log:@"执行搜索模式二 - 第一次搜索"];
        [ScannerState shared].scanId = 生成扫描id();
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kSearchStartNotification object:nil];
        
        // 执行首次搜索
        执行首次搜索(target, data_type, type, type_size);
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:kSearchStartNotification object:nil];
        // 执行再次搜索
        [LoggingService log:@"执行再次搜索"];
        执行再次搜索(target, data_type, type, type_size);
    }
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
    
    // 创建线程安全的计数器和互斥锁
    __block atomic_size_t local_match_count = 0;
    pthread_mutex_t *file_mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    pthread_mutex_init(file_mutex, NULL);
    
    mach_port_t task = mach_task_self();
    std::vector<区域范围> memoryRegions = 收集有效内存区域();
    
    [LoggingService log:@"找到 %lu 个有效内存区域，开始并行搜索", (unsigned long)memoryRegions.size()];
    
    // 创建并行队列
    dispatch_queue_t searchQueue = dispatch_queue_create("com.memory.search.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t searchGroup = dispatch_group_create();
    
    // 低内存自适应：限制并发 + 缩减块大小
    int exactMaxConcurrency = 低内存自适应并发数();
    dispatch_semaphore_t exactConcurrencySem = (exactMaxConcurrency > 0)
        ? dispatch_semaphore_create(exactMaxConcurrency)
        : NULL;
    const size_t EXACT_CHUNK = 低内存自适应块大小();

    [LoggingService log:@"精确首次搜索 - 块大小: %zuKB, 最大并发: %d", EXACT_CHUNK / 1024, exactMaxConcurrency];

    // 并行处理每个内存区域
    for (const 区域范围& region : memoryRegions) {
        vm_address_t region_start = region.start;
        size_t region_size = region.size;

        if (exactConcurrencySem) dispatch_semaphore_wait(exactConcurrencySem, DISPATCH_TIME_FOREVER);

        dispatch_group_enter(searchGroup);
        dispatch_async(searchQueue, ^{
            for (size_t offset = 0; offset < region_size; offset += EXACT_CHUNK) {
                size_t chunk_size = (offset + EXACT_CHUNK > region_size) ? (region_size - offset) : EXACT_CHUNK;
                void* buffer = malloc(chunk_size);
                
                if (!buffer) {
                    [LoggingService log:@"无法分配内存块缓冲区，大小: %zu", chunk_size];
                    continue;
                }
                
                mach_vm_size_t out_size;
                kern_return_t kr = mach_vm_read_overwrite(task, region_start + offset, chunk_size, (mach_vm_address_t)buffer, &out_size);
                
                if (kr == KERN_SUCCESS && out_size == chunk_size) {
                    // 本地结果缓冲区，减少锁竞争
                    AddressValuePair* local_results = (AddressValuePair*)malloc(sizeof(AddressValuePair) * 1024);
                    size_t local_count = 0;
                    size_t local_capacity = 1024;
                    
                    size_t values_count = chunk_size / type_size;
                    for (size_t j = 0; j < values_count; j++) {
                        uint64_t curr_address = region_start + offset + (j * type_size);
                        if ((curr_address % type_size) != 0) continue; // 跳过未对齐的地址
                        
                        void* curr_val = (char*)buffer + (j * type_size);
                        
                        // 使用统一的比较值函数
                        if (比较值(curr_val, NULL, &target, data_type, 精确)) {
                            // 扩展本地结果缓冲区（如果需要）
                            if (local_count >= local_capacity) {
                                local_capacity *= 2;
                                AddressValuePair* new_buffer = (AddressValuePair*)realloc(local_results, sizeof(AddressValuePair) * local_capacity);
                                if (!new_buffer) {
                                    [LoggingService log:@"无法扩展本地结果缓冲区"];
                                    break;
                                }
                                local_results = new_buffer;
                            }
                            
                            // 添加到本地结果
                            local_results[local_count].address = curr_address;
                            memcpy(local_results[local_count].bytes, curr_val, type_size);
                            local_count++;
                        }
                    }
                    
                    // 批量写入结果文件
                    if (local_count > 0) {
                        pthread_mutex_lock(file_mutex);
                        size_t written = fwrite(local_results, sizeof(AddressValuePair), local_count, result_fp);
                        pthread_mutex_unlock(file_mutex);
                        
                        atomic_fetch_add(&local_match_count, written);
                    }
                    
                    free(local_results);
                }
                
                free(buffer);
            }
            
            dispatch_group_leave(searchGroup);
            if (exactConcurrencySem) dispatch_semaphore_signal(exactConcurrencySem);
        });
    }
    
    // 等待所有搜索任务完成
    dispatch_group_wait(searchGroup, DISPATCH_TIME_FOREVER);
    
    size_t match_count = atomic_load(&local_match_count);
    
    fclose(result_fp);
    pthread_mutex_destroy(file_mutex);
    free(file_mutex);
    
    if (search_results->result_file_path) {
        free(search_results->result_file_path);
    }
    search_results->result_file_path = result_path;
    search_results->count = match_count;
    [LoggingService log:@"精确搜索完成，找到 %zu 个匹配结果", match_count];
    
    // 处理回调
    处理搜索结果回调(match_count, result_path);
    
    // 标记已完成首次搜索
    global_scanner->previous_values = (void*)malloc(sizeof(int));
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
    [ScannerState shared].memoryCapacity = 2048; // 初始容量
    [ScannerState shared].memory = (MemoryEntry*)malloc(sizeof(MemoryEntry) * global_memory_capacity);
    [ScannerState shared].memoryCount = 0;
    
    // 3. 创建结果文件的互斥锁和计数器
    __block atomic_size_t processed_count = 0;
    pthread_mutex_t *dump_mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    pthread_mutex_init(dump_mutex, NULL);

    // 如果没有区域信息，则进行内存范围扫描
    if (global_memory_count == 0) {
        [LoggingService log:@"执行模糊首次搜索 - 开始收集内存区域"];
        
        mach_port_t task = mach_task_self();
        std::vector<区域范围> memoryRegions = 收集有效内存区域();
        
        [LoggingService log:@"找到 %lu 个有效内存区域，开始并行处理", (unsigned long)memoryRegions.size()];
        
        // 创建并行队列和组
        dispatch_queue_t processQueue = dispatch_queue_create("com.memory.process.queue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_group_t processGroup = dispatch_group_create();
        
        // 低内存设备：限制并发数，避免峰值叠加导致 jetsam
        int maxConcurrency = 低内存自适应并发数();
        dispatch_semaphore_t concurrencySem = (maxConcurrency > 0)
            ? dispatch_semaphore_create(maxConcurrency)
            : NULL;
        const size_t ADAPTIVE_CHUNK_SIZE = 低内存自适应块大小();
        const size_t MEMORY_PRESSURE_THRESHOLD = (ADAPTIVE_CHUNK_SIZE <= 2 * 1024 * 1024)
            ? (size_t)(获取物理内存大小() * 0.15)   // 1GB 设备：当可用内存 < 总内存的 15% 时暂停
            : 0;  // 大内存设备不监控

        [LoggingService log:@"模糊首次搜索 - 自适应块大小: %zuKB, 最大并发: %d (物理内存: %lluMB)",
            ADAPTIVE_CHUNK_SIZE / 1024,
            maxConcurrency,
            获取物理内存大小() / (1024 * 1024)];

        // 并行处理每个内存区域
        for (const 区域范围& region : memoryRegions) {
            vm_address_t region_start = region.start;
            size_t region_size = region.size;

            // 并发限制：大内存设备不限制，低内存设备串行化或限流
            if (concurrencySem) dispatch_semaphore_wait(concurrencySem, DISPATCH_TIME_FOREVER);

            dispatch_group_enter(processGroup);
            dispatch_async(processQueue, ^{
                for (size_t offset = 0; offset < region_size; offset += ADAPTIVE_CHUNK_SIZE) {
                    // 低内存保护：可用内存不足时短暂让出 CPU（500ms 缓存，避免频繁 sysctl）
                    if (检查内存压力(MEMORY_PRESSURE_THRESHOLD)) {
                        usleep(50000);  // 50ms 让出
                    }

                    size_t chunk_size = (offset + ADAPTIVE_CHUNK_SIZE > region_size)
                        ? (region_size - offset)
                        : ADAPTIVE_CHUNK_SIZE;

                    // 分步分配：先读后压，避免 读缓冲+压缩缓冲 同时占据峰值
                    void* buffer = malloc(chunk_size);
                    if (!buffer) {
                        [LoggingService log:@"⚠️ 内存不足，跳过块 0x%llX+%zu", region_start + offset, chunk_size];
                        continue;
                    }

                    mach_vm_size_t out_size;
                    kern_return_t kr = mach_vm_read_overwrite(task,
                        region_start + offset, chunk_size,
                        (mach_vm_address_t)buffer, &out_size);

                    if (kr != KERN_SUCCESS || out_size != chunk_size) {
                        free(buffer);
                        continue;
                    }

                    // 读取成功后，计算压缩上限
                    int max_compressed_size = LZ4_compressBound((int)chunk_size);
                    void* compressed_buffer = malloc(max_compressed_size);

                    if (!compressed_buffer) {
                        // 压缩缓冲区分配失败：降级写入原始数据
                        // 依赖 is_compressed 标记，下游从原始数据比较 会据此选择 memcpy 而非 LZ4 解压
                        [LoggingService log:@"⚠️ 压缩缓冲区分配失败，降级写原始数据 块 0x%llX+%zu", region_start + offset, chunk_size];
                        pthread_mutex_lock(dump_mutex);
                        if (global_memory_count >= global_memory_capacity) {
                            size_t new_capacity = global_memory_capacity * 2;
                            MemoryEntry* new_memory = (MemoryEntry*)realloc(
                                global_memory, new_capacity * sizeof(MemoryEntry));
                            if (new_memory) {
                                [ScannerState shared].memory = new_memory;
                                [ScannerState shared].memoryCapacity = new_capacity;
                            } else {
                                pthread_mutex_unlock(dump_mutex);
                                free(buffer);
                                continue;
                            }
                        }
                        long raw_offset = ftell(dump_fp);
                        if (fwrite(buffer, 1, chunk_size, dump_fp) == chunk_size) {
                            MemoryEntry entry = {};
                            entry.address = region_start + offset;
                            entry.file_offset = (uint64_t)raw_offset;
                            entry.compressed_size = chunk_size;
                            entry.uncompressed_size = chunk_size;
                            entry.is_first = true;
                            entry.is_compressed = false;   // 标记为原始数据
                            global_memory[global_memory_count++] = entry;
                            atomic_fetch_add(&processed_count, 1);
                        }
                        pthread_mutex_unlock(dump_mutex);
                        free(buffer);
                        continue;
                    }

                    // 正常压缩路径
                    int compressed_size = LZ4_compress_default(
                        (const char*)buffer, (char*)compressed_buffer,
                        (int)chunk_size, max_compressed_size);

                    if (compressed_size > 0) {
                        // 释放读缓冲（尽早释放，降低峰值）
                        free(buffer);
                        buffer = NULL;

                        pthread_mutex_lock(dump_mutex);

                        // 检查并扩展容量
                        if (global_memory_count >= global_memory_capacity) {
                            size_t new_capacity = global_memory_capacity * 2;
                            MemoryEntry* new_memory = (MemoryEntry*)realloc(
                                global_memory, new_capacity * sizeof(MemoryEntry));
                            if (new_memory) {
                                [ScannerState shared].memory = new_memory;
                                [ScannerState shared].memoryCapacity = new_capacity;
                            } else {
                                [LoggingService log:@"⚠️ global_memory realloc 失败(容量 %zu)，丢弃块 0x%llX", global_memory_capacity, region_start + offset];
                                pthread_mutex_unlock(dump_mutex);
                                free(compressed_buffer);
                                continue;
                            }
                        }

                        long current_offset = ftell(dump_fp);
                        if (fwrite(compressed_buffer, 1, (size_t)compressed_size, dump_fp)
                            == (size_t)compressed_size) {
                            MemoryEntry entry = {};
                            entry.address = region_start + offset;
                            entry.file_offset = (uint64_t)current_offset;
                            entry.compressed_size = (size_t)compressed_size;
                            entry.uncompressed_size = chunk_size;
                            entry.is_first = true;
                            entry.is_compressed = true;    // 标记为 LZ4 压缩
                            global_memory[global_memory_count++] = entry;
                            atomic_fetch_add(&processed_count, 1);
                        }

                        pthread_mutex_unlock(dump_mutex);
                        free(compressed_buffer);
                    } else {
                        // 压缩失败，释放资源
                        free(buffer);
                        free(compressed_buffer);
                    }
                }
                dispatch_group_leave(processGroup);
                if (concurrencySem) dispatch_semaphore_signal(concurrencySem);
            });
        }
        
        // 等待所有处理任务完成
        dispatch_group_wait(processGroup, DISPATCH_TIME_FOREVER);
        
        size_t total_processed = atomic_load(&processed_count);
        [LoggingService log:@"内存扫描完成，共找到并存储 %zu 个内存区域", total_processed];
    }
    
    fclose(dump_fp);
    pthread_mutex_destroy(dump_mutex);
    free(dump_mutex);
    
    // 初始化结果集（模糊搜索首次结果为空，等待下一次搜索）
    if (search_results->result_file_path) {
        free(search_results->result_file_path);
        search_results->result_file_path = NULL;
    }
    search_results->count = 0;
    
    [LoggingService log:@"模糊首次搜索快照完成，准备进行后续变化搜索"];
    
    // 处理回调，通知UI更新
    // 即使是模糊搜索首次（match_count=0），我们也传递当前的 type 参数，以便UI层区分是"无结果"还是"初始化完成"
    处理搜索结果回调(0, NULL);
    
    // 标记已完成首次搜索
    global_scanner->previous_values = (void*)malloc(sizeof(int));
}

// ╔══════════════════════════════════════════╗
// ║  4. 再次搜索                             ║
// ║  过滤模式(从结果筛选) ▸ 快照模式(全量对比) ║
// ╚══════════════════════════════════════════╝

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

    // 逻辑修正：
    // 1. 如果有上一次的搜索结果（search_results->count > 0），说明是精确搜索/区间搜索后的再次搜索，或者已经经过筛选的模糊搜索。
    //    此时应该在现有结果集的基础上进一步筛选（性能最优）。
    // 2. 如果结果集为空，但有内存快照（global_memory_count > 0），说明是“未知初始值”后的第一次具体搜索。
    //    此时必须从全量快照中进行对比筛选。
    
    if (search_results && search_results->count > 0 && search_results->result_file_path) {
        // 从上一次结果进行比较 (Filter Mode)
        [LoggingService log:@"执行再次搜索 - 基于已有结果集 (%zu 个)", search_results->count];
        match_count = 从上次结果比较(target, data_type, type, type_size, new_fp);
    } else if (global_memory_count > 0) {
        // 从原始数据进行比较 (Snapshot Mode)
        [LoggingService log:@"执行再次搜索 - 基于内存快照 (%zu 个块)", global_memory_count];
        match_count = 从原始数据比较(target, data_type, type, type_size, new_fp);
    } else {
        [LoggingService log:@"错误：没有可用的搜索基础（既无结果集也无快照）"];
    }
    
    fclose(new_fp);
    
    if (search_results->result_file_path) {
        free(search_results->result_file_path);
    }
    search_results->result_file_path = new_result_path;
    search_results->count = match_count;
    
    [LoggingService log:@"再次搜索完成，找到 %zu 个匹配结果", match_count];
    
    // 处理回调
    处理搜索结果回调(match_count, new_result_path);
}

/// 快照模式再次搜索：mmap 旧 dump → GCD 并行逐块解压/对比 → 增量写新 dump
/// 已变化块重新 LZ4 压缩，未变化块直接复用旧压缩数据
size_t 从原始数据比较(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size, FILE* result_fp) {
    [LoggingService log:@"从原始数据进行比较 - 并行处理 (mmap优化版)"];
    
    if (!global_dump_file_path) {
        [LoggingService log:@"错误：没有全局转储文件"];
        return 0;
    }
    
    // 1. 打开并映射旧的全局转储文件
    int old_fd = open(global_dump_file_path, O_RDONLY);
    if (old_fd < 0) {
        [LoggingService log:@"无法打开旧的转储文件"];
        return 0;
    }
    
    struct stat st;
    if (fstat(old_fd, &st) != 0 || st.st_size == 0) {
        close(old_fd);
        return 0;
    }
    size_t file_size = (size_t)st.st_size;
    
    void* mapped_data = mmap(NULL, file_size, PROT_READ, MAP_SHARED, old_fd, 0);
    if (mapped_data == MAP_FAILED) {
        [LoggingService log:@"mmap 失败"];
        close(old_fd);
        return 0;
    }
    close(old_fd);
    
    // 2. 准备新的全局转储文件
    char* new_dump_path = 创建临时文件();
    if (!new_dump_path) {
        munmap(mapped_data, file_size);
        return 0;
    }
    
    FILE* new_dump_fp = fopen(new_dump_path, "wb");
    if (!new_dump_fp) {
        free(new_dump_path);
        munmap(mapped_data, file_size);
        return 0;
    }
    
    // 3. 创建线程安全的计数器和互斥锁
    __block atomic_size_t local_match_count = 0;
    pthread_mutex_t *result_mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    pthread_mutex_init(result_mutex, NULL);
    
    pthread_mutex_t *dump_mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    pthread_mutex_init(dump_mutex, NULL);
    
    // 4. 低内存自适应：限制并发，避免 previous+current 双缓冲叠加压垮内存
    int cmpMaxConcurrency = 低内存自适应并发数();
    dispatch_semaphore_t cmpConcurrencySem = (cmpMaxConcurrency > 0)
        ? dispatch_semaphore_create(cmpMaxConcurrency)
        : NULL;
    dispatch_queue_t processQueue = dispatch_queue_create("com.memory.compare.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t processGroup = dispatch_group_create();
    
    [LoggingService log:@"快照再次搜索 - 条目数: %zu, 最大并发: %d", global_memory_count, cmpMaxConcurrency];
        
    // 并行处理每个内存区域
    for (size_t i = 0; i < global_memory_count; i++) {
        MemoryEntry* entry = &global_memory[i];
            
        if (cmpConcurrencySem) dispatch_semaphore_wait(cmpConcurrencySem, DISPATCH_TIME_FOREVER);
    
        dispatch_group_enter(processGroup);
        dispatch_async(processQueue, ^{
            // 获取旧的文件偏移 (必须在更新前获取)
            uint64_t old_offset = entry->file_offset;
                
            // 边界检查
            if (old_offset + entry->compressed_size > file_size) {
                 dispatch_group_leave(processGroup);
                 if (cmpConcurrencySem) dispatch_semaphore_signal(cmpConcurrencySem);
                 return;
            }
                
            // 直接从映射内存中获取数据（压缩或原始）
            const char* local_data = (const char*)mapped_data + old_offset;
                
            // 解压/复制旧数据
            void* previous_buffer = malloc(entry->uncompressed_size);
            if (!previous_buffer) {
                [LoggingService log:@"⚠️ 再次搜索: previous_buffer 分配失败(块 0x%llX, 大小 %zu)，跳过", entry->address, entry->uncompressed_size];
                dispatch_group_leave(processGroup);
                if (cmpConcurrencySem) dispatch_semaphore_signal(cmpConcurrencySem);
                return;
            }

            if (entry->is_compressed) {
                // LZ4 压缩数据：解压
                if (LZ4_decompress_safe(local_data, (char*)previous_buffer,
                        (int)entry->compressed_size, (int)entry->uncompressed_size) <= 0) {
                    [LoggingService log:@"⚠️ 再次搜索: LZ4 解压失败(块 0x%llX, compressed=%zu, uncompressed=%zu)，跳过", entry->address, entry->compressed_size, entry->uncompressed_size];
                    free(previous_buffer);
                    dispatch_group_leave(processGroup);
                    if (cmpConcurrencySem) dispatch_semaphore_signal(cmpConcurrencySem);
                    return;
                }
            } else {
                // 原始数据：直接复制
                memcpy(previous_buffer, local_data, entry->uncompressed_size);
            }
                
            // 5. 读取当前内存数据
            void* current_buffer = malloc(entry->uncompressed_size);
            if (!current_buffer) {
                [LoggingService log:@"⚠️ 再次搜索: current_buffer 分配失败(块 0x%llX, 大小 %zu)，跳过", entry->address, entry->uncompressed_size];
                free(previous_buffer);
                dispatch_group_leave(processGroup);
                if (cmpConcurrencySem) dispatch_semaphore_signal(cmpConcurrencySem);
                return;
            }
                
            mach_vm_size_t out_size;
            kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), entry->address, entry->uncompressed_size, (mach_vm_address_t)current_buffer, &out_size);
                
            if (kr == KERN_SUCCESS) {
                // 检查数据块是否发生变化
                bool is_changed = memcmp(current_buffer, previous_buffer, entry->uncompressed_size) != 0;
                    
                // 6. 比较数据 (如果需要)
                // 只有当搜索类型是"变化"、"增加了"、"减少了"且数据块未变时，才跳过比较
                bool skip_compare = !is_changed && (type == 变化 || type == 增加了 || type == 减少了 || type == 增加了多少 || type == 减少了多少);
                    
                if (!skip_compare) {
                    AddressValuePair* local_results = (AddressValuePair*)malloc(sizeof(AddressValuePair) * 1024);
                    size_t local_count = 0;
                    size_t local_capacity = 1024;
                        
                    size_t values_count = entry->uncompressed_size / type_size;
                        
                    for (size_t j = 0; j < values_count; j++) {
                        uint64_t curr_address = entry->address + (j * type_size);
                        if ((curr_address % type_size) != 0) continue;
                            
                        void* curr_val = (char*)current_buffer + (j * type_size);
                        void* prev_val = (char*)previous_buffer + (j * type_size);
                            
                        if (比较值(curr_val, prev_val, &target, data_type, type)) {
                            if (local_count >= local_capacity) {
                                local_capacity *= 2;
                                AddressValuePair* new_buffer = (AddressValuePair*)realloc(local_results, sizeof(AddressValuePair) * local_capacity);
                                if (!new_buffer) break;
                                local_results = new_buffer;
                            }
                                
                            local_results[local_count].address = curr_address;
                            memcpy(local_results[local_count].bytes, curr_val, type_size);
                            local_count++;
                        }
                    }
                        
                    // 写入搜索结果
                    if (local_count > 0) {
                        pthread_mutex_lock(result_mutex);
                        size_t written = fwrite(local_results, sizeof(AddressValuePair), local_count, result_fp);
                        pthread_mutex_unlock(result_mutex);
                        atomic_fetch_add(&local_match_count, written);
                    }
                    free(local_results);
                }
                    
                // 7. 写入新的转储文件 (增量更新优化)
                if (!is_changed) {
                    // 数据块未变，直接复用旧数据（压缩或原始格式保持一致）
                    pthread_mutex_lock(dump_mutex);
                    long new_offset = ftell(new_dump_fp);
                    if (fwrite(local_data, 1, entry->compressed_size, new_dump_fp) == entry->compressed_size) {
                        entry->file_offset = (uint64_t)new_offset;
                        // compressed_size 和 is_compressed 不变
                    }
                    pthread_mutex_unlock(dump_mutex);
                } else {
                    // 数据块已变，重新压缩并写入（统一转为 LZ4 压缩格式）
                    int max_compressed_size = LZ4_compressBound((int)entry->uncompressed_size);
                    void* new_compressed_buffer = malloc(max_compressed_size);
                        
                    if (new_compressed_buffer) {
                        int new_compressed_size = LZ4_compress_default((const char*)current_buffer, (char*)new_compressed_buffer, (int)entry->uncompressed_size, max_compressed_size);
                            
                        if (new_compressed_size > 0) {
                            pthread_mutex_lock(dump_mutex);
                            long new_offset = ftell(new_dump_fp);
                            if (fwrite(new_compressed_buffer, 1, (size_t)new_compressed_size, new_dump_fp) == (size_t)new_compressed_size) {
                                entry->file_offset = (uint64_t)new_offset;
                                entry->compressed_size = new_compressed_size;
                                entry->is_compressed = true;  // 已转为压缩格式
                            }
                            pthread_mutex_unlock(dump_mutex);
                        }
                        free(new_compressed_buffer);
                    } else {
                        // 压缩缓冲区分配失败：降级写原始数据
                        [LoggingService log:@"⚠️ 再次搜索: 压缩缓冲区分配失败，降级写原始数据 块 0x%llX", entry->address];
                        pthread_mutex_lock(dump_mutex);
                        long new_offset = ftell(new_dump_fp);
                        if (fwrite(current_buffer, 1, entry->uncompressed_size, new_dump_fp) == entry->uncompressed_size) {
                            entry->file_offset = (uint64_t)new_offset;
                            entry->compressed_size = entry->uncompressed_size;
                            entry->is_compressed = false;
                        }
                        pthread_mutex_unlock(dump_mutex);
                    }
                }
            }
                
            free(previous_buffer);
            free(current_buffer);
            dispatch_group_leave(processGroup);
            if (cmpConcurrencySem) dispatch_semaphore_signal(cmpConcurrencySem);
        });
    }
    
    // 等待所有处理任务完成
    dispatch_group_wait(processGroup, DISPATCH_TIME_FOREVER);
    
    // 清理映射
    munmap(mapped_data, file_size);
    
    // 8. 清理和更新全局状态
    fclose(new_dump_fp);
    pthread_mutex_destroy(result_mutex);
    pthread_mutex_destroy(dump_mutex);
    free(result_mutex);
    free(dump_mutex);
    
    // 替换全局转储文件路径
    if (global_dump_file_path) {
        删除临时文件(global_dump_file_path);
        free(global_dump_file_path);
    }
    [ScannerState shared].dumpFilePath = new_dump_path;
    
    size_t match_count = atomic_load(&local_match_count);
    [LoggingService log:@"从原始数据比较完成，找到 %zu 个匹配结果", match_count];
    
    // 标记已完成首次再搜索
    if (!global_scanner->previous_values) {
        global_scanner->previous_values = (void*)malloc(sizeof(int));
    }
    
    return match_count;
}

/// 过滤模式再次搜索：顺序遍历上次结果文件，逐地址重新读取后对比
/// 使用栈缓冲 current_value[8] 避免 per-result malloc
size_t 从上次结果比较(数值 target, 数据类型 data_type, 对比类型 type, size_t type_size, FILE* new_fp) {
    [LoggingService log:@"从上一次结果进行比较"];
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
    
    AddressValuePair old_pair;
    uint8_t current_value[8];  // 栈缓冲，max type_size=8，消除 per-result malloc/free
    while (fread(&old_pair, sizeof(AddressValuePair), 1, old_fp) == 1) {
        if ((old_pair.address % type_size) != 0) continue; // 跳过未对齐的地址

        mach_vm_size_t out_size;
        kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), old_pair.address, type_size, (mach_vm_address_t)current_value, &out_size);
        
        if (kr == KERN_SUCCESS && out_size == type_size) {
            // 使用统一的比较值函数
            if (比较值(current_value, old_pair.bytes, &target, data_type, type)) {
                AddressValuePair pair = {};
                pair.address = old_pair.address;
                memcpy(pair.bytes, current_value, type_size);
                
                if (fwrite(&pair, sizeof(AddressValuePair), 1, new_fp) == 1) {
                    match_count++;
                }
            }
        }
    }
    
    fclose(old_fp);
    return match_count;
}

// ╔══════════════════════════════════════════╗
// ║  5. 结果回调                             ║
// ╚══════════════════════════════════════════╝

/// 将搜索结果文件中的地址读入数组，通过 search_callback 回调主线程
/// match_count=0 时仅通知 UI，不清除快照
void 处理搜索结果回调(size_t match_count, const char* result_path) {
    if (search_callback) {
        if (match_count == 0) {
            // 当搜索结果为0时，仅通知UI更新，不自动清理
            // 模糊搜索（首次）结果也为0，但此时不应清理，否则会丢失快照
            [LoggingService log:@"搜索结果为0 (或是模糊首次搜索)，通知UI更新"];
            dispatch_async(dispatch_get_main_queue(), ^{
                search_callback(NULL, 0, 当前数据类型);
            });
            return;
        }
        
        uint64_t* callback_results = (uint64_t*)malloc(match_count * sizeof(uint64_t));
        if (callback_results) {
            FILE* read_fp = fopen(result_path, "rb");
            if (read_fp) {
                size_t index = 0;
                AddressValuePair pair;
                
                while (fread(&pair, sizeof(AddressValuePair), 1, read_fp) == 1 && index < match_count) {
                    callback_results[index++] = pair.address;
                }
                
                fclose(read_fp);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [LoggingService log:@"准备调用搜索回调 - 地址数量: %zu", match_count];
                    search_callback(callback_results, match_count, 当前数据类型);
                    free(callback_results);
                });
            }
        }
    }
}
