// 指针链解析 / 求值核心（纯 C++17）。
//
// 原实现把字符串解析、NSDictionary 组装、mach 读内存混在 Objective-C 里。
// 这里只保留纯逻辑：
//   - 表达式解析成 SSChainStep 数组；
//   - 求值时通过 SSChainReadFn 回调读内存。
// Objective-C 适配层（PointerChainParser.m）负责 NSArray/NSError 和 mach 调用。

#include "Core/Algorithms/SSPointerChainCore.h"

#include <algorithm>
#include <cctype>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace {

std::string trim(std::string_view s) {
    size_t b = 0, e = s.size();
    while (b < e && std::isspace(static_cast<unsigned char>(s[b]))) b++;
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) e--;
    return std::string(s.substr(b, e - b));
}

std::string lower_ascii(std::string s) {
    for (char& c : s) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
}

std::string remove_spaces(std::string s) {
    s.erase(std::remove_if(s.begin(), s.end(),
                           [](unsigned char c) { return std::isspace(c) != 0; }),
            s.end());
    return s;
}

std::string remove_char(std::string s, char c) {
    s.erase(std::remove(s.begin(), s.end(), c), s.end());
    return s;
}

bool has_hex_prefix(const std::string& s) {
    return s.size() >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X');
}

uint64_t parse_hex(const std::string& s) {
    const std::string cleaned = remove_spaces(s);
    if (cleaned.empty()) return 0;
    return std::strtoull(cleaned.c_str(), nullptr, 16);
}

std::vector<std::string> split(const std::string& s, const std::string& delim) {
    std::vector<std::string> out;
    size_t start = 0;
    for (;;) {
        const size_t pos = s.find(delim, start);
        if (pos == std::string::npos) {
            out.push_back(s.substr(start));
            break;
        }
        out.push_back(s.substr(start, pos - start));
        start = pos + delim.size();
    }
    return out;
}

size_t fail(int code, const char* message, int* error_code, char* error, size_t error_size) {
    if (error_code) *error_code = code;
    if (error && error_size) std::snprintf(error, error_size, "%s", message);
    return 0;
}

bool add_step(SSChainStep* steps, size_t capacity, size_t& count,
              SSChainStepType type, uint64_t offset, const std::string& module) {
    if (count >= capacity) return false;
    SSChainStep& step = steps[count];
    std::memset(&step, 0, sizeof(step));
    step.type = type;
    step.offset = offset;
    if (!module.empty()) {
        std::strncpy(step.module, module.c_str(), sizeof(step.module) - 1);
        step.module[sizeof(step.module) - 1] = '\0';
    }
    count++;
    return true;
}

void log_message(SSChainLogFn log, void* context, const char* format, ...) {
    if (!log) return;
    char buffer[512];
    va_list args;
    va_start(args, format);
    std::vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    log(buffer, context);
}

} // namespace

extern "C" size_t ss_chain_parse(const char* expression, SSChainStep* steps, size_t capacity,
                                 SSChainLogFn log, void* context,
                                 int* error_code, char* error, size_t error_size) {
    if (error_code) *error_code = 0;
    if (error && error_size) error[0] = '\0';

    if (!steps || capacity == 0) {
        return fail(-1, "没有可写入的步骤缓冲区", error_code, error, error_size);
    }

    const std::string expr = trim(expression ? std::string_view(expression) : std::string_view());
    if (expr.empty()) {
        return fail(-1, "表达式为空", error_code, error, error_size);
    }

    std::string delimiter;
    if (expr.find("->") != std::string::npos) {
        delimiter = "->";
    } else if (expr.find(',') != std::string::npos) {
        delimiter = ",";
    } else if (expr.find(';') != std::string::npos) {
        delimiter = ";";
    } else if (expr.find('|') != std::string::npos) {
        delimiter = "|";
    }

    size_t count = 0;

    if (!delimiter.empty()) {
        // 格式 1: [模块+偏移] 分隔符 +偏移 分隔符 +偏移
        const std::vector<std::string> components = split(expr, delimiter);
        std::string base = trim(components[0]);

        if (base.size() < 2 || base.front() != '[' || base.back() != ']') {
            return fail(-3, "基址部分缺少 []", error_code, error, error_size);
        }

        const std::string inner = trim(std::string_view(base).substr(1, base.size() - 2));
        const std::vector<std::string> base_parts = split(inner, "+");

        if (base_parts.size() >= 2) {
            const std::string module = lower_ascii(trim(base_parts[0]));
            const uint64_t offset = parse_hex(trim(base_parts[1]));
            if (!add_step(steps, capacity, count, SS_CHAIN_STEP_MODULE, offset, module)) {
                return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
            }
            log_message(log, context, "[解析] 模块: %s, 偏移: 0x%llX",
                        module.c_str(), static_cast<unsigned long long>(offset));
        } else if (base_parts.size() == 1) {
            const std::string module = lower_ascii(trim(base_parts[0]));
            if (!add_step(steps, capacity, count, SS_CHAIN_STEP_MODULE, 0, module)) {
                return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
            }
            log_message(log, context, "[解析] 模块: %s (无偏移)", module.c_str());
        } else {
            return fail(-2, "基址格式错误: 应为 [模块 + 偏移]", error_code, error, error_size);
        }

        for (size_t i = 1; i < components.size(); i++) {
            std::string offset_str = trim(components[i]);
            offset_str = remove_char(offset_str, '+');
            offset_str = remove_spaces(offset_str);
            if (offset_str.empty()) continue;

            const uint64_t offset = parse_hex(offset_str);
            if (!add_step(steps, capacity, count, SS_CHAIN_STEP_POINTER, offset, std::string())) {
                return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
            }
            log_message(log, context, "[解析] 指针偏移: 0x%llX",
                        static_cast<unsigned long long>(offset));
        }
    } else if (expr.size() >= 2 && expr.front() == '[' && expr.back() == ']') {
        // 格式 2: [模块+偏移] 或 [模块]
        const std::string inner = trim(std::string_view(expr).substr(1, expr.size() - 2));

        if (inner.find('+') != std::string::npos) {
            const std::vector<std::string> parts = split(inner, "+");
            if (parts.size() >= 2) {
                const std::string module = lower_ascii(trim(parts[0]));
                const uint64_t offset = parse_hex(trim(parts[1]));
                if (!add_step(steps, capacity, count, SS_CHAIN_STEP_MODULE, offset, module)) {
                    return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
                }
                log_message(log, context, "[解析] 模块地址: [%s + 0x%llX]",
                            module.c_str(), static_cast<unsigned long long>(offset));
            } else {
                return fail(-2, "格式错误: 应为 [模块 + 偏移]", error_code, error, error_size);
            }
        } else {
            const std::string module = lower_ascii(inner);
            if (!add_step(steps, capacity, count, SS_CHAIN_STEP_MODULE, 0, module)) {
                return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
            }
            log_message(log, context, "[解析] 模块基址: [%s]", module.c_str());
        }
    } else if (has_hex_prefix(expr)) {
        // 格式 3: 0x地址 + 偏移 + 偏移
        const std::vector<std::string> components = split(expr, "+");

        const uint64_t base = parse_hex(trim(components[0]));
        if (!add_step(steps, capacity, count, SS_CHAIN_STEP_ADDRESS, base, std::string())) {
            return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
        }
        log_message(log, context, "[解析] 基址: 0x%llX", static_cast<unsigned long long>(base));

        for (size_t i = 1; i < components.size(); i++) {
            std::string offset_str = remove_spaces(trim(components[i]));
            if (!has_hex_prefix(offset_str)) {
                offset_str = "0x" + offset_str;
            }
            const uint64_t offset = parse_hex(offset_str);
            if (!add_step(steps, capacity, count, SS_CHAIN_STEP_POINTER, offset, std::string())) {
                return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
            }
            log_message(log, context, "[解析] 指针偏移: 0x%llX",
                        static_cast<unsigned long long>(offset));
        }
    } else {
        // 格式 4: 模块+偏移 或 模块
        if (expr.find('+') != std::string::npos) {
            const std::vector<std::string> parts = split(expr, "+");
            if (parts.size() >= 2) {
                const std::string module = lower_ascii(trim(parts[0]));
                std::string offset_str = remove_spaces(trim(parts[1]));
                if (!has_hex_prefix(offset_str)) {
                    offset_str = "0x" + offset_str;
                }
                const uint64_t offset = parse_hex(offset_str);
                if (!add_step(steps, capacity, count, SS_CHAIN_STEP_MODULE, offset, module)) {
                    return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
                }
                log_message(log, context, "[解析] 模块地址: %s + 0x%llX",
                            module.c_str(), static_cast<unsigned long long>(offset));
            } else {
                return fail(-2, "格式错误: 应为 模块 + 偏移", error_code, error, error_size);
            }
        } else {
            const std::string module = lower_ascii(expr);
            if (!add_step(steps, capacity, count, SS_CHAIN_STEP_MODULE, 0, module)) {
                return fail(-6, "指针链过长（最多 64 步）", error_code, error, error_size);
            }
            log_message(log, context, "[解析] 模块基址: %s", module.c_str());
        }
    }

    if (count == 0) {
        return fail(-5, "解析结果为空", error_code, error, error_size);
    }

    return count;
}

extern "C" uint64_t ss_chain_resolve(const SSChainStep* steps, size_t count, uint64_t module_base,
                                     SSChainReadFn read, SSChainLogFn log, void* context,
                                     int* status, char* error, size_t error_size) {
    if (status) *status = 0;
    if (error && error_size) error[0] = '\0';

    char local_error[SS_CHAIN_ERROR_MAX] = {0};
    char* err = (error && error_size) ? error : local_error;
    const size_t err_size = (error && error_size) ? error_size : sizeof(local_error);

    if (!steps || count == 0) {
        if (status) *status = -1;
        std::snprintf(err, err_size, "%s", "空指针链");
        return 0;
    }

    uint64_t current = 0;
    for (size_t i = 0; i < count; i++) {
        const SSChainStep& step = steps[i];
        switch (step.type) {
            case SS_CHAIN_STEP_MODULE:
                current = module_base + step.offset;
                log_message(log, context, "[指针链] 模块基址: 0x%llX + 偏移: 0x%llX = 0x%llX",
                            static_cast<unsigned long long>(module_base),
                            static_cast<unsigned long long>(step.offset),
                            static_cast<unsigned long long>(current));
                break;

            case SS_CHAIN_STEP_ADDRESS:
                current = step.offset;
                log_message(log, context, "[指针链] 直接地址: 0x%llX",
                            static_cast<unsigned long long>(current));
                break;

            case SS_CHAIN_STEP_POINTER: {
                if (!read) {
                    if (status) *status = -1;
                    std::snprintf(err, err_size, "%s", "没有可用的内存读取回调");
                    return 0;
                }

                uint64_t pointer_value = 0;
                const int rc = read(current, &pointer_value, context);
                if (rc != 0) {
                    if (status) *status = rc;
                    std::snprintf(err, err_size, "读取地址 0x%llX 失败 (错误码: %d)",
                                  static_cast<unsigned long long>(current), rc);
                    log_message(log, context, "[指针链] 错误: %s", err);
                    return 0;
                }

                current = pointer_value + step.offset;
                log_message(log, context, "[指针链] 读取指针: 0x%llX + 偏移: 0x%llX = 0x%llX",
                            static_cast<unsigned long long>(pointer_value),
                            static_cast<unsigned long long>(step.offset),
                            static_cast<unsigned long long>(current));
                break;
            }

            default:
                break;
        }
    }

    log_message(log, context, "[指针链] 最终地址: 0x%llX",
                static_cast<unsigned long long>(current));
    return current;
}
