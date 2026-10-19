// 值扫描内核（纯 C++17）。
//
// 这里只做“字节 → 命中”的纯算法：不包含 Foundation / UIKit / ScannerState。
// 对外通过 ScannerKernel.h / Scanner.h 的 C ABI 暴露，由 Objective-C 侧
// （Scanner.mm / ScannerConfig.m）负责线程、文件、通知等编排。
//
// 设备（arm64）走 NEON 快路径；主机侧单元测试没有 NEON 时自动退回标量实现，
// 两条路径的语义保持一致。

#include "Modules/Scanner/ScannerKernel.h"

#include <cmath>
#include <cstdint>
#include <cstring>

#if defined(__ARM_NEON)
#include <arm_neon.h>
#define SS_SCAN_HAS_NEON 1
#else
#define SS_SCAN_HAS_NEON 0
#endif

namespace {

inline void 记一条(AddressValuePair *out, size_t i, uint64_t addr, const void *v, size_t n) {
    out[i].address = addr;
    std::memset(out[i].bytes, 0, sizeof(out[i].bytes));
    std::memcpy(out[i].bytes, v, n);
}

template <typename T>
inline T 取目标(const 数值 *t) {
    T v;
    std::memcpy(&v, t->bytes, sizeof(T));
    return v;
}

// ───────────────────────── 精确 ─────────────────────────

static size_t 精确_u8(const uint8_t *buf, size_t bytes, uint64_t base, uint8_t 目标,
                      AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    size_t total = 0, n = 0;
    const uint8_t *p = buf;
    const uint8_t *end = buf + bytes;
    while (p < end) {
        const uint8_t *hit = static_cast<const uint8_t *>(std::memchr(p, 目标, static_cast<size_t>(end - p)));
        if (!hit) break;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(hit - buf), hit, 1);
        n++;
        p = hit + 1;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

#if SS_SCAN_HAS_NEON

static size_t 精确_u16(const uint8_t *buf, size_t bytes, uint64_t base, uint16_t 目标,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const uint16_t *p = reinterpret_cast<const uint16_t *>(buf);
    size_t count = bytes / 2, total = 0, n = 0, i = 0;
    uint16x8_t tv = vdupq_n_u16(目标);
    while (i + 8 <= count) {
        uint16x8_t eq = vceqq_u16(vld1q_u16(p + i), tv);
        if (vmaxvq_u16(eq) == 0) { i += 8; continue; }
        uint16_t m[8];
        vst1q_u16(m, eq);
        for (size_t k = 0; k < 8; k++) {
            if (!m[k]) continue;
            if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
            记一条(out, n, base + static_cast<uint64_t>(i + k) * 2, p + i + k, 2);
            n++;
        }
        i += 8;
    }
    for (; i < count; i++) {
        if (p[i] != 目标) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * 2, p + i, 2);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

static size_t 精确_u32(const uint8_t *buf, size_t bytes, uint64_t base, uint32_t 目标,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const uint32_t *p = reinterpret_cast<const uint32_t *>(buf);
    size_t count = bytes / 4, total = 0, n = 0, i = 0;
    uint32x4_t tv = vdupq_n_u32(目标);
    while (i + 4 <= count) {
        uint32x4_t eq = vceqq_u32(vld1q_u32(p + i), tv);
        if (vmaxvq_u32(eq) == 0) { i += 4; continue; }
        uint32_t m[4];
        vst1q_u32(m, eq);
        for (size_t k = 0; k < 4; k++) {
            if (!m[k]) continue;
            if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
            记一条(out, n, base + static_cast<uint64_t>(i + k) * 4, p + i + k, 4);
            n++;
        }
        i += 4;
    }
    for (; i < count; i++) {
        if (p[i] != 目标) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * 4, p + i, 4);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

static size_t 精确_u64(const uint8_t *buf, size_t bytes, uint64_t base, uint64_t 目标,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const uint64_t *p = reinterpret_cast<const uint64_t *>(buf);
    size_t count = bytes / 8, total = 0, n = 0, i = 0;
    uint64x2_t tv = vdupq_n_u64(目标);
    while (i + 2 <= count) {
        uint64x2_t eq = vceqq_u64(vld1q_u64(p + i), tv);
        uint64_t m[2];
        vst1q_u64(m, eq);
        if ((m[0] | m[1]) == 0) { i += 2; continue; }
        for (size_t k = 0; k < 2; k++) {
            if (!m[k]) continue;
            if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
            记一条(out, n, base + static_cast<uint64_t>(i + k) * 8, p + i + k, 8);
            n++;
        }
        i += 2;
    }
    for (; i < count; i++) {
        if (p[i] != 目标) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * 8, p + i, 8);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

#else // !SS_SCAN_HAS_NEON

template <typename T>
static size_t 精确_标量(const uint8_t *buf, size_t bytes, uint64_t base, T 目标,
                        AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const T *p = reinterpret_cast<const T *>(buf);
    const size_t count = bytes / sizeof(T);
    size_t total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        if (p[i] != 目标) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * sizeof(T), p + i, sizeof(T));
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

static inline size_t 精确_u16(const uint8_t *buf, size_t bytes, uint64_t base, uint16_t 目标,
                              AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    return 精确_标量<uint16_t>(buf, bytes, base, 目标, out, cap, 提交, ctx);
}

static inline size_t 精确_u32(const uint8_t *buf, size_t bytes, uint64_t base, uint32_t 目标,
                              AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    return 精确_标量<uint32_t>(buf, bytes, base, 目标, out, cap, 提交, ctx);
}

static inline size_t 精确_u64(const uint8_t *buf, size_t bytes, uint64_t base, uint64_t 目标,
                              AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    return 精确_标量<uint64_t>(buf, bytes, base, 目标, out, cap, 提交, ctx);
}

#endif // SS_SCAN_HAS_NEON

// ───────────────────────── 区间 ─────────────────────────

template <typename T>
static size_t 区间扫描(const uint8_t *buf, size_t bytes, uint64_t base, T 下, T 上,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const T *p = reinterpret_cast<const T *>(buf);
    const size_t count = bytes / sizeof(T);
    size_t total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        if (!(p[i] >= 下 && p[i] <= 上)) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * sizeof(T), p + i, sizeof(T));
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

// ───────────────────────── 变化 / 不变 ─────────────────────────

template <typename T>
[[maybe_unused]] static size_t 变化扫描_标量(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                                            AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const size_t 元素 = sizeof(T);
    const size_t count = bytes / 元素;
    size_t total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        const uint8_t *c = cur + i * 元素;
        const uint8_t *p = prev + i * 元素;
        if (std::memcmp(c, p, 元素) == 0) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * 元素, c, 元素);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

#if SS_SCAN_HAS_NEON

template <typename T>
static size_t 变化扫描(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const size_t 元素 = sizeof(T);
    const size_t k = 16 / 元素;
    const size_t count = bytes / 元素;
    size_t total = 0, n = 0, i = 0;
    for (; i + k <= count; i += k) {
        uint8x16_t a = vld1q_u8(cur + i * 元素);
        uint8x16_t b = vld1q_u8(prev + i * 元素);
        if (vminvq_u8(vceqq_u8(a, b)) == 0xFF) continue;   // 16 字节全等，整段跳过
        for (size_t j = 0; j < k; j++) {
            const uint8_t *c = cur + (i + j) * 元素;
            const uint8_t *p = prev + (i + j) * 元素;
            if (std::memcmp(c, p, 元素) == 0) continue;
            if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
            记一条(out, n, base + static_cast<uint64_t>(i + j) * 元素, c, 元素);
            n++;
        }
    }
    for (; i < count; i++) {
        const uint8_t *c = cur + i * 元素;
        const uint8_t *p = prev + i * 元素;
        if (std::memcmp(c, p, 元素) == 0) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * 元素, c, 元素);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

#else

template <typename T>
static size_t 变化扫描(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    return 变化扫描_标量<T>(cur, prev, bytes, base, out, cap, 提交, ctx);
}

#endif // SS_SCAN_HAS_NEON

template <typename T>
static size_t 不变扫描(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const size_t count = bytes / sizeof(T);
    const uint8_t 零[8] = {0};
    size_t total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        const uint8_t *c = cur + i * sizeof(T);
        const uint8_t *p = prev + i * sizeof(T);
        if (std::memcmp(c, p, sizeof(T)) != 0) continue;
        if (std::memcmp(c, 零, sizeof(T)) == 0) continue;      // 与旧行为一致：全零不算“不变”
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * sizeof(T), c, sizeof(T));
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

// ───────────────────────── 增加 / 减少 ─────────────────────────

template <typename T>
static size_t 增减_整数(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                       对比类型 操作, T 阈值, AddressValuePair *out, size_t cap,
                       扫描提交 提交, void *ctx) {
    const T *c = reinterpret_cast<const T *>(cur);
    const T *p = reinterpret_cast<const T *>(prev);
    const size_t count = bytes / sizeof(T);
    size_t total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        bool 命中 = false;
        switch (操作) {
            case 增加了:     命中 = c[i] > p[i]; break;
            case 减少了:     命中 = c[i] < p[i]; break;
            case 增加了多少: 命中 = (static_cast<int64_t>(c[i]) - static_cast<int64_t>(p[i])) == static_cast<int64_t>(阈值); break;
            case 减少了多少: 命中 = (static_cast<int64_t>(p[i]) - static_cast<int64_t>(c[i])) == static_cast<int64_t>(阈值); break;
            default: break;
        }
        if (!命中) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * sizeof(T), c + i, sizeof(T));
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

template <typename T>
static size_t 增减_浮点(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                       对比类型 操作, T 阈值, AddressValuePair *out, size_t cap,
                       扫描提交 提交, void *ctx) {
    const T *c = reinterpret_cast<const T *>(cur);
    const T *p = reinterpret_cast<const T *>(prev);
    const T 误差 = static_cast<T>(0.0001);
    const size_t count = bytes / sizeof(T);
    size_t total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        bool 命中 = false;
        switch (操作) {
            case 增加了:     命中 = c[i] > p[i]; break;
            case 减少了:     命中 = c[i] < p[i]; break;
            case 增加了多少: 命中 = std::fabs(static_cast<double>((c[i] - p[i]) - 阈值)) < static_cast<double>(误差); break;
            case 减少了多少: 命中 = std::fabs(static_cast<double>((p[i] - c[i]) - 阈值)) < static_cast<double>(误差); break;
            default: break;
        }
        if (!命中) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + static_cast<uint64_t>(i) * sizeof(T), c + i, sizeof(T));
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

template <typename T>
static size_t 双值_整数(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                       对比类型 操作, const 数值 *目标, AddressValuePair *out, size_t cap,
                       扫描提交 提交, void *ctx) {
    switch (操作) {
        case 变化: return 变化扫描<T>(cur, prev, bytes, base, out, cap, 提交, ctx);
        case 不变: return 不变扫描<T>(cur, prev, bytes, base, out, cap, 提交, ctx);
        default: break;
    }
    T 阈值 = T();
    std::memcpy(&阈值, 目标->bytes, sizeof(T));
    return 增减_整数<T>(cur, prev, bytes, base, 操作, 阈值, out, cap, 提交, ctx);
}

template <typename T>
static size_t 双值_浮点(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                       对比类型 操作, const 数值 *目标, AddressValuePair *out, size_t cap,
                       扫描提交 提交, void *ctx) {
    switch (操作) {
        case 变化: return 变化扫描<T>(cur, prev, bytes, base, out, cap, 提交, ctx);
        case 不变: return 不变扫描<T>(cur, prev, bytes, base, out, cap, 提交, ctx);
        default: break;
    }
    T 阈值 = T();
    std::memcpy(&阈值, 目标->bytes, sizeof(T));
    return 增减_浮点<T>(cur, prev, bytes, base, 操作, 阈值, out, cap, 提交, ctx);
}

} // namespace

extern "C" size_t 获取类型大小(数据类型 type) {
    switch (type) {
        case 类型_字节: return sizeof(uint8_t);
        case 类型_短整数: return sizeof(int16_t);
        case 类型_整数: return sizeof(int32_t);
        case 类型_长整数: return sizeof(int64_t);
        case 类型_浮点: return sizeof(float);
        case 类型_双精度: return sizeof(double);
        default: return sizeof(int32_t);
    }
}

extern "C" bool 比较值(const void *current, const void *previous, const void *target,
                       数据类型 data_type, 对比类型 type) {
    if (!current) return false;

    const size_t size = 获取类型大小(data_type);
    const uint8_t *curr = static_cast<const uint8_t *>(current);
    const uint8_t *prev = static_cast<const uint8_t *>(previous);
    const uint8_t *tgt = static_cast<const uint8_t *>(target);

    // 区间比较
    if (type == 区间) {
        const 数值 *value = static_cast<const 数值 *>(target);
        if (!value) return false;

        switch (data_type) {
            case 类型_字节: {
                uint8_t val = *reinterpret_cast<const uint8_t *>(current);
                return val >= (value->range_i.min & 0xFF) && val <= (value->range_i.max & 0xFF);
            }
            case 类型_短整数: {
                int16_t val = *reinterpret_cast<const int16_t *>(current);
                return val >= static_cast<int16_t>(value->range_i.min & 0xFFFF) &&
                       val <= static_cast<int16_t>(value->range_i.max & 0xFFFF);
            }
            case 类型_整数: {
                int32_t val = *reinterpret_cast<const int32_t *>(current);
                return val >= value->range_i.min && val <= value->range_i.max;
            }
            case 类型_长整数: {
                int64_t val = *reinterpret_cast<const int64_t *>(current);
                return val >= value->range_l.min && val <= value->range_l.max;
            }
            case 类型_浮点: {
                float val = *reinterpret_cast<const float *>(current);
                return val >= value->range_f.min && val <= value->range_f.max;
            }
            case 类型_双精度: {
                double val = *reinterpret_cast<const double *>(current);
                return val >= value->range_d.min && val <= value->range_d.max;
            }
        }
        return false;
    }

    if (!tgt) return false;

    // 精确匹配
    if (type == 精确) {
        return std::memcmp(curr, tgt, size) == 0;
    }

    // 需要旧值的比较：旧值不存在时一律不匹配，避免空指针解引用
    if (!prev) return false;

    // 变化和不变
    if (type == 变化) {
        return std::memcmp(curr, prev, size) != 0;
    }
    if (type == 不变) {
        static const uint8_t 零[8] = {0};
        return std::memcmp(curr, prev, size) == 0 && std::memcmp(curr, 零, size) != 0;
    }

    // 数值比较
    if (type == 增加了 || type == 减少了 || type == 增加了多少 || type == 减少了多少) {
        switch (data_type) {
            case 类型_字节: {
                uint8_t c = *reinterpret_cast<const uint8_t *>(current);
                uint8_t p = *reinterpret_cast<const uint8_t *>(previous);
                uint8_t t = *reinterpret_cast<const uint8_t *>(target);

                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return (c > p) && ((c - p) == t);
                if (type == 减少了多少) return (p > c) && ((p - c) == t);
                break;
            }
            case 类型_短整数: {
                int16_t c = *reinterpret_cast<const int16_t *>(current);
                int16_t p = *reinterpret_cast<const int16_t *>(previous);
                int16_t t = *reinterpret_cast<const int16_t *>(target);

                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return static_cast<int64_t>(c) - static_cast<int64_t>(p) == t;
                if (type == 减少了多少) return static_cast<int64_t>(p) - static_cast<int64_t>(c) == t;
                break;
            }
            case 类型_整数: {
                int32_t c = *reinterpret_cast<const int32_t *>(current);
                int32_t p = *reinterpret_cast<const int32_t *>(previous);
                int32_t t = *reinterpret_cast<const int32_t *>(target);

                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return static_cast<int64_t>(c) - static_cast<int64_t>(p) == t;
                if (type == 减少了多少) return static_cast<int64_t>(p) - static_cast<int64_t>(c) == t;
                break;
            }
            case 类型_长整数: {
                int64_t c = *reinterpret_cast<const int64_t *>(current);
                int64_t p = *reinterpret_cast<const int64_t *>(previous);
                int64_t t = *reinterpret_cast<const int64_t *>(target);

                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return (c - p) == t;
                if (type == 减少了多少) return (p - c) == t;
                break;
            }
            case 类型_浮点: {
                float c = *reinterpret_cast<const float *>(current);
                float p = *reinterpret_cast<const float *>(previous);
                float t = *reinterpret_cast<const float *>(target);
                const float epsilon = 0.0001f;

                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return std::fabs((c - p) - t) < epsilon;
                if (type == 减少了多少) return std::fabs((p - c) - t) < epsilon;
                break;
            }
            case 类型_双精度: {
                double c = *reinterpret_cast<const double *>(current);
                double p = *reinterpret_cast<const double *>(previous);
                double t = *reinterpret_cast<const double *>(target);
                const double epsilon = 0.0001;

                if (type == 增加了) return c > p;
                if (type == 减少了) return c < p;
                if (type == 增加了多少) return std::fabs((c - p) - t) < epsilon;
                if (type == 减少了多少) return std::fabs((p - c) - t) < epsilon;
                break;
            }
        }
    }

    return false;
}

extern "C" size_t 扫描块_单值(const uint8_t *当前, size_t 字节数, uint64_t 基址,
                              数据类型 类型, 对比类型 操作, const 数值 *目标,
                              AddressValuePair *暂存, size_t 暂存容量,
                              扫描提交 提交, void *上下文) {
    if (!当前 || !目标 || !暂存 || 暂存容量 == 0 || 字节数 == 0) return 0;
    if (操作 == 精确) {
        switch (类型) {
            case 类型_字节:   return 精确_u8(当前, 字节数, 基址, 取目标<uint8_t>(目标), 暂存, 暂存容量, 提交, 上下文);
            case 类型_短整数: return 精确_u16(当前, 字节数, 基址, 取目标<uint16_t>(目标), 暂存, 暂存容量, 提交, 上下文);
            case 类型_整数:   return 精确_u32(当前, 字节数, 基址, 取目标<uint32_t>(目标), 暂存, 暂存容量, 提交, 上下文);
            case 类型_长整数: return 精确_u64(当前, 字节数, 基址, 取目标<uint64_t>(目标), 暂存, 暂存容量, 提交, 上下文);
            case 类型_浮点:   return 精确_u32(当前, 字节数, 基址, 取目标<uint32_t>(目标), 暂存, 暂存容量, 提交, 上下文);
            case 类型_双精度: return 精确_u64(当前, 字节数, 基址, 取目标<uint64_t>(目标), 暂存, 暂存容量, 提交, 上下文);
        }
        return 0;
    }
    if (操作 == 区间) {
        switch (类型) {
            case 类型_字节:
                return 区间扫描<uint8_t>(当前, 字节数, 基址,
                    static_cast<uint8_t>(目标->range_i.min & 0xFF),
                    static_cast<uint8_t>(目标->range_i.max & 0xFF),
                    暂存, 暂存容量, 提交, 上下文);
            case 类型_短整数:
                return 区间扫描<int16_t>(当前, 字节数, 基址,
                    static_cast<int16_t>(目标->range_i.min),
                    static_cast<int16_t>(目标->range_i.max),
                    暂存, 暂存容量, 提交, 上下文);
            case 类型_整数:
                return 区间扫描<int32_t>(当前, 字节数, 基址,
                    目标->range_i.min, 目标->range_i.max, 暂存, 暂存容量, 提交, 上下文);
            case 类型_长整数:
                return 区间扫描<int64_t>(当前, 字节数, 基址,
                    目标->range_l.min, 目标->range_l.max, 暂存, 暂存容量, 提交, 上下文);
            case 类型_浮点:
                return 区间扫描<float>(当前, 字节数, 基址,
                    目标->range_f.min, 目标->range_f.max, 暂存, 暂存容量, 提交, 上下文);
            case 类型_双精度:
                return 区间扫描<double>(当前, 字节数, 基址,
                    目标->range_d.min, 目标->range_d.max, 暂存, 暂存容量, 提交, 上下文);
        }
    }
    return 0;
}

extern "C" size_t 扫描块_双值(const uint8_t *当前, const uint8_t *旧值, size_t 字节数, uint64_t 基址,
                              数据类型 类型, 对比类型 操作, const 数值 *目标,
                              AddressValuePair *暂存, size_t 暂存容量,
                              扫描提交 提交, void *上下文) {
    if (!当前 || !旧值 || !目标 || !暂存 || 暂存容量 == 0 || 字节数 == 0) return 0;
    switch (类型) {
        case 类型_字节:   return 双值_整数<uint8_t>(当前, 旧值, 字节数, 基址, 操作, 目标, 暂存, 暂存容量, 提交, 上下文);
        case 类型_短整数: return 双值_整数<int16_t>(当前, 旧值, 字节数, 基址, 操作, 目标, 暂存, 暂存容量, 提交, 上下文);
        case 类型_整数:   return 双值_整数<int32_t>(当前, 旧值, 字节数, 基址, 操作, 目标, 暂存, 暂存容量, 提交, 上下文);
        case 类型_长整数: return 双值_整数<int64_t>(当前, 旧值, 字节数, 基址, 操作, 目标, 暂存, 暂存容量, 提交, 上下文);
        case 类型_浮点:   return 双值_浮点<float>(当前, 旧值, 字节数, 基址, 操作, 目标, 暂存, 暂存容量, 提交, 上下文);
        case 类型_双精度: return 双值_浮点<double>(当前, 旧值, 字节数, 基址, 操作, 目标, 暂存, 暂存容量, 提交, 上下文);
    }
    return 0;
}
