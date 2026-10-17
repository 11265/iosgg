#import "Modules/Scanner/SignatureScanner.h"
#import "Services/LogService.h"
#import <ctype.h>
#import "Modules/ProcessInfo/ProcessMemory.h"

// 特征码结果上限：和值搜索同量级，避免异常特征码扫出天量命中
#define 最大特征码结果数 (2000000)

// 全局变量
static SignatureSearchCallback signature_search_callback = NULL;

// 添加设置回调函数
void 设置特征码搜索回调(SignatureSearchCallback callback) {
    signature_search_callback = callback;
}

// 解析特征码字符串为结构体
SearchPattern* 解析特征码(const char* pattern) {
    if (!pattern) return NULL;
    
    SearchPattern* result = malloc(sizeof(SearchPattern));
    if (!result) return NULL;
    
    // 计算特征码长度(去除空格后的字节数)
    size_t pattern_len = strlen(pattern);
    size_t byte_count = 0;
    for (size_t i = 0; i < pattern_len; i++) {
        if (pattern[i] != ' ') byte_count++;
    }
    byte_count = byte_count / 2; // 每个字节由两个字符表示
    
    result->bytes = malloc(byte_count * sizeof(PatternByte));
    if (!result->bytes) {
        free(result);
        return NULL;
    }
    result->length = byte_count;
    
    // 解析每个字节
    size_t byte_index = 0;
    char hex[3] = {0};
    size_t hex_index = 0;
    
    for (size_t i = 0; i < pattern_len; i++) {
        if (pattern[i] == ' ') continue;
        
        hex[hex_index++] = pattern[i];
        
        if (hex_index == 2) {
            PatternByte* curr_byte = &result->bytes[byte_index];
            
            if (strcmp(hex, "??") == 0) {
                curr_byte->is_wildcard = true;
                curr_byte->byte = 0;
            } else {
                curr_byte->is_wildcard = false;
                sscanf(hex, "%hhx", &curr_byte->byte);
            }
            
            byte_index++;
            hex_index = 0;
        }
    }
    
    return result;
}

// 添加 Sunday 算法的移动表计算函数
static void 计算移动表(const SearchPattern* pattern, size_t* move_table) {
    // 初始化移动表，默认移动长度为模式长度 + 1
    for (size_t i = 0; i < 256; i++) {
        move_table[i] = pattern->length + 1;
    }
    
    // 计算每个字节的移动距离
    for (size_t i = 0; i < pattern->length; i++) {
        if (!pattern->bytes[i].is_wildcard) {
            move_table[pattern->bytes[i].byte] = pattern->length - i;
        }
    }
}

// 修改检查匹配函数，使用 Sunday 算法
static bool 检查匹配(const uint8_t* memory, size_t memory_size, 
                  const SearchPattern* pattern, size_t offset) {
    if (offset + pattern->length > memory_size) return false;
    
    for (size_t i = 0; i < pattern->length; i++) {
        if (!pattern->bytes[i].is_wildcard && 
            memory[offset + i] != pattern->bytes[i].byte) {
            return false;
        }
    }
    return true;
}

// 修改搜索模式三函数，使用 Sunday 算法
void 搜索模式三(const char* pattern) {
    [LoggingService log:@"执行特征码搜索 - 模式: %s", pattern];
    
    SearchPattern* search_pattern = 解析特征码(pattern);
    if (!search_pattern) {
        [LoggingService log:@"特征码解析失败"];
        return;
    }

    if (search_pattern->length == 0) {
        [LoggingService log:@"特征码为空，已取消搜索"];
        释放特征码(search_pattern);
        return;
    }
    
    // 创建移动表
    size_t move_table[256];
    计算移动表(search_pattern, move_table);
    
    // 创建内存缓冲区存储匹配结果
    size_t initial_capacity = 1024;
    uint64_t* results = malloc(initial_capacity * sizeof(uint64_t));
    size_t result_count = 0;
    size_t current_capacity = initial_capacity;
    size_t 溢出条数 = 0;    // 超过上限、未保存的命中数（只计数，不落盘）
    
    if (!results) {
        释放特征码(search_pattern);
        [LoggingService log:@"无法分配结果缓冲区"];
        return;
    }
    
    mach_port_t task = mach_task_self();
    vm_address_t address = 0;
    
    while (true) {
        vm_size_t size;
        natural_t depth = 0;
        vm_region_submap_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        
        kern_return_t kr = vm_region_recurse_64(task, &address, &size, &depth,
                                              (vm_region_info_t)&info, &count);
        
        if (kr == KERN_INVALID_ADDRESS) break;
        if (kr != KERN_SUCCESS) {
            address += size;
            continue;
        }
        
        // 检查地址范围
        if (address >= SIGNATURE_SEARCH_RANGE_END) break;
        if (address + size <= SIGNATURE_SEARCH_RANGE_START) {
            address += size;
            continue;
        }

        // 计算有效范围
        vm_address_t valid_start = address < SIGNATURE_SEARCH_RANGE_START ? SIGNATURE_SEARCH_RANGE_START : address;
        vm_address_t valid_end = (address + size) > SIGNATURE_SEARCH_RANGE_END ? SIGNATURE_SEARCH_RANGE_END : (address + size);
        size_t adjusted_size = valid_end - valid_start;
        
        if (adjusted_size < search_pattern->length) {
            address += size;
            continue;
        }
        if (info.protection & VM_PROT_READ) {
            void* buffer = malloc(adjusted_size);
            if (!buffer) {
                address += size;
                continue;
            }
            
            mach_vm_size_t out_size;
            kr = mach_vm_read_overwrite(task, valid_start, adjusted_size,
                                      (mach_vm_address_t)buffer, &out_size);
            
            if (kr == KERN_SUCCESS && out_size == adjusted_size) {
                // 使用 Sunday 算法搜索特征码
                size_t pos = 0;
                while (pos <= adjusted_size - search_pattern->length) {
                    if (检查匹配(buffer, adjusted_size, search_pattern, pos)) {
                        uint64_t match_address = valid_start + pos;
                        
                        // 达到上限后不再保存，但继续扫描并计数 —— 不能跳过剩余内存
                        if (result_count >= (size_t)最大特征码结果数) {
                            溢出条数++;
                        } else {
                            // 检查是否需要扩展缓冲区
                            if (result_count >= current_capacity) {
                                size_t new_capacity = current_capacity * 2;
                                uint64_t* new_results = realloc(results, new_capacity * sizeof(uint64_t));
                                if (!new_results) {
                                    [LoggingService log:@"无法扩展结果缓冲区，停止本次扫描"];
                                    break;
                                }
                                results = new_results;
                                current_capacity = new_capacity;
                            }
                            
                            results[result_count++] = match_address;
                            if (result_count <= 5) {
                                [LoggingService log:@"找到匹配: 0x%llx", match_address];
                            }
                        }
                    }
                    
                    // Sunday 算法的移动
                    if (pos + search_pattern->length >= adjusted_size) break;
                    uint8_t next_byte = ((uint8_t*)buffer)[pos + search_pattern->length];
                    pos += move_table[next_byte];
                }
            }
            
            free(buffer);
        }
        
        address += size;
    }
    
    if (溢出条数 > 0) {
        [LoggingService log:@"特征码搜索完成：命中 %zu 条，保留 %zu 条（超过上限，其余未保留）",
            result_count + 溢出条数, result_count];
    } else {
        [LoggingService log:@"特征码搜索完成，找到 %zu 个匹配结果", result_count];
    }
    
    // 使用专用回调
    if (result_count > 0 && signature_search_callback) {
        signature_search_callback(results, result_count);
    }
    
    // 清理资源
    free(results);
    释放特征码(search_pattern);
}

// 修改释放特征码函数，添加日志
void 释放特征码(SearchPattern* pattern) {
    if (pattern) {
        if (pattern->bytes) {
            free(pattern->bytes);
            pattern->bytes = NULL;
        }
        free(pattern);
        [LoggingService log:@"特征码资源已释放"];
    }
} 