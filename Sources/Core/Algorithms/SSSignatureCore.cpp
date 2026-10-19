// 特征码扫描核心（纯 C++17）。
//
// 职责：把 "48 8B ?? 00" 解析成模式，并在给定缓冲区上跑 Sunday 匹配。
// 不包含 mach / Foundation：区域枚举与内存读取留在 SignatureScanner.m，
// 这样算法可以在主机上用 g++ 直接做单元测试。

#include "Modules/Scanner/SignatureScanner.h"

#include <array>
#include <cctype>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace {

int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

} // namespace

extern "C" SearchPattern* 解析特征码(const char* pattern) {
    if (!pattern) return nullptr;

    std::string_view text(pattern);
    std::vector<PatternByte> parsed;
    parsed.reserve(text.size() / 2);

    char token[2] = {0, 0};
    size_t nibbles = 0;

    for (char ch : text) {
        if (std::isspace(static_cast<unsigned char>(ch))) continue;

        token[nibbles++] = ch;
        if (nibbles != 2) continue;

        PatternByte pb{};
        if (token[0] == '?' && token[1] == '?') {
            pb.is_wildcard = true;
            pb.byte = 0;
        } else {
            const int hi = hex_value(token[0]);
            const int lo = hex_value(token[1]);
            if (hi < 0 || lo < 0) {
                // 非法十六进制：整条模式判为无效，避免旧实现里未初始化的字节
                return nullptr;
            }
            pb.is_wildcard = false;
            pb.byte = static_cast<uint8_t>((hi << 4) | lo);
        }
        parsed.push_back(pb);
        nibbles = 0;
    }

    // 奇数个非空白字符：最后一个半字节与旧实现一致，直接忽略。
    SearchPattern* result = static_cast<SearchPattern*>(std::malloc(sizeof(SearchPattern)));
    if (!result) return nullptr;

    result->length = parsed.size();
    result->bytes = nullptr;
    if (!parsed.empty()) {
        result->bytes = static_cast<PatternByte*>(std::malloc(parsed.size() * sizeof(PatternByte)));
        if (!result->bytes) {
            std::free(result);
            return nullptr;
        }
        for (size_t i = 0; i < parsed.size(); i++) {
            result->bytes[i] = parsed[i];
        }
    }
    return result;
}

extern "C" void 释放特征码(SearchPattern* pattern) {
    if (!pattern) return;
    std::free(pattern->bytes);
    pattern->bytes = nullptr;
    pattern->length = 0;
    std::free(pattern);
}

extern "C" size_t 扫描特征码缓冲区(const SearchPattern* pattern, const uint8_t* buffer, size_t size,
                                   uint64_t base, SignatureMatchCallback on_match, void* context) {
    if (!pattern || !buffer || pattern->length == 0 || size < pattern->length) return 0;

    const size_t 长度 = pattern->length;

    // Sunday 算法的移动表：默认跳过 长度+1，模式内字符按最右出现位置回退。
    std::array<size_t, 256> move{};
    move.fill(长度 + 1);
    for (size_t i = 0; i < 长度; i++) {
        if (!pattern->bytes[i].is_wildcard) {
            move[pattern->bytes[i].byte] = 长度 - i;
        }
    }

    size_t pos = 0;
    size_t total = 0;

    while (pos + 长度 <= size) {
        bool matched = true;
        for (size_t i = 0; i < 长度; i++) {
            if (!pattern->bytes[i].is_wildcard && buffer[pos + i] != pattern->bytes[i].byte) {
                matched = false;
                break;
            }
        }

        if (matched) {
            if (on_match) on_match(context, base + static_cast<uint64_t>(pos));
            total++;
        }

        if (pos + 长度 >= size) break;
        const uint8_t next_byte = buffer[pos + 长度];
        pos += move[next_byte];
    }

    return total;
}
