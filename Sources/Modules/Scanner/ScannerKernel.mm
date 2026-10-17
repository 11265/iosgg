// 扫描内核：按 (数据类型 × 对比类型) 特化，热路径不再每值调用一次 比较值()。
// 精确匹配走 NEON（u8 走 memchr），变化检测按 16 字节向量先判"整段未变"。
#import "Modules/Scanner/ScannerKernel.h"
#include <string.h>
#include <math.h>
#include <arm_neon.h>

namespace {

static inline void 记一条(AddressValuePair *out, size_t i, uint64_t addr, const void *v, size_t n) {
    out[i].address = addr;
    memset(out[i].bytes, 0, sizeof(out[i].bytes));
    memcpy(out[i].bytes, v, n);
}

template <typename T>
static inline T 取目标(const 数值 *t) {
    T v;
    memcpy(&v, t->bytes, sizeof(T));
    return v;
}

// ───────────────────────── 精确 ─────────────────────────

static size_t 精确_u8(const uint8_t *buf, size_t bytes, uint64_t base, uint8_t 目标,
                      AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    size_t total = 0, n = 0;
    const uint8_t *p = buf;
    const uint8_t *end = buf + bytes;
    while (p < end) {
        const uint8_t *hit = (const uint8_t *)memchr(p, 目标, (size_t)(end - p));
        if (!hit) break;
        记一条(out, n, base + (uint64_t)(hit - buf), hit, 1);
        n++;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        p = hit + 1;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

static size_t 精确_u16(const uint8_t *buf, size_t bytes, uint64_t base, uint16_t 目标,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const uint16_t *p = (const uint16_t *)buf;
    size_t count = bytes / 2, total = 0, n = 0, i = 0;
    uint16x8_t tv = vdupq_n_u16(目标);
    while (i + 8 <= count) {
        uint16x8_t eq = vceqq_u16(vld1q_u16(p + i), tv);
        if (vmaxvq_u16(eq) == 0) { i += 8; continue; }
        if (n + 8 > cap) { 提交(ctx, out, n); total += n; n = 0; }
        uint16_t m[8];
        vst1q_u16(m, eq);
        for (size_t k = 0; k < 8; k++) {
            if (!m[k]) continue;
            记一条(out, n, base + (uint64_t)(i + k) * 2, p + i + k, 2);
            n++;
        }
        i += 8;
    }
    for (; i < count; i++) {
        if (p[i] != 目标) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * 2, p + i, 2);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

static size_t 精确_u32(const uint8_t *buf, size_t bytes, uint64_t base, uint32_t 目标,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const uint32_t *p = (const uint32_t *)buf;
    size_t count = bytes / 4, total = 0, n = 0, i = 0;
    uint32x4_t tv = vdupq_n_u32(目标);
    while (i + 4 <= count) {
        uint32x4_t eq = vceqq_u32(vld1q_u32(p + i), tv);
        if (vmaxvq_u32(eq) == 0) { i += 4; continue; }
        if (n + 4 > cap) { 提交(ctx, out, n); total += n; n = 0; }
        uint32_t m[4];
        vst1q_u32(m, eq);
        for (size_t k = 0; k < 4; k++) {
            if (!m[k]) continue;
            记一条(out, n, base + (uint64_t)(i + k) * 4, p + i + k, 4);
            n++;
        }
        i += 4;
    }
    for (; i < count; i++) {
        if (p[i] != 目标) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * 4, p + i, 4);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

static size_t 精确_u64(const uint8_t *buf, size_t bytes, uint64_t base, uint64_t 目标,
                       AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const uint64_t *p = (const uint64_t *)buf;
    size_t count = bytes / 8, total = 0, n = 0, i = 0;
    uint64x2_t tv = vdupq_n_u64(目标);
    while (i + 2 <= count) {
        uint64x2_t eq = vceqq_u64(vld1q_u64(p + i), tv);
        uint64_t m[2];
        vst1q_u64(m, eq);
        if ((m[0] | m[1]) == 0) { i += 2; continue; }
        if (n + 2 > cap) { 提交(ctx, out, n); total += n; n = 0; }
        for (size_t k = 0; k < 2; k++) {
            if (!m[k]) continue;
            记一条(out, n, base + (uint64_t)(i + k) * 8, p + i + k, 8);
            n++;
        }
        i += 2;
    }
    for (; i < count; i++) {
        if (p[i] != 目标) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * 8, p + i, 8);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

// ───────────────────────── 区间 ─────────────────────────

template <typename T>
static size_t 区间扫描(const uint8_t *buf, size_t bytes, uint64_t base, T 下, T 上,
                   AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const T *p = (const T *)buf;
    size_t count = bytes / sizeof(T), total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        if (!(p[i] >= 下 && p[i] <= 上)) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * sizeof(T), p + i, sizeof(T));
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

// ───────────────────────── 变化 / 不变 ─────────────────────────

template <typename T>
static size_t 变化扫描(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                   AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    const size_t 元素 = sizeof(T);
    const size_t k = 16 / 元素;
    size_t count = bytes / 元素, total = 0, n = 0, i = 0;
    for (; i + k <= count; i += k) {
        uint8x16_t a = vld1q_u8(cur + i * 元素);
        uint8x16_t b = vld1q_u8(prev + i * 元素);
        if (vminvq_u8(vceqq_u8(a, b)) == 0xFF) continue;   // 16 字节全等，整段跳过
        for (size_t j = 0; j < k; j++) {
            const uint8_t *c = cur + (i + j) * 元素;
            const uint8_t *p = prev + (i + j) * 元素;
            if (memcmp(c, p, 元素) == 0) continue;
            if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
            记一条(out, n, base + (uint64_t)(i + j) * 元素, c, 元素);
            n++;
        }
    }
    for (; i < count; i++) {
        const uint8_t *c = cur + i * 元素;
        const uint8_t *p = prev + i * 元素;
        if (memcmp(c, p, 元素) == 0) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * 元素, c, 元素);
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

template <typename T>
static size_t 不变扫描(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                   AddressValuePair *out, size_t cap, 扫描提交 提交, void *ctx) {
    size_t count = bytes / sizeof(T), total = 0, n = 0;
    const uint8_t 零[8] = {0};
    for (size_t i = 0; i < count; i++) {
        const uint8_t *c = cur + i * sizeof(T);
        const uint8_t *p = prev + i * sizeof(T);
        if (memcmp(c, p, sizeof(T)) != 0) continue;
        if (memcmp(c, 零, sizeof(T)) == 0) continue;      // 与旧行为一致：全零不算"不变"
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * sizeof(T), c, sizeof(T));
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
    const T *c = (const T *)cur;
    const T *p = (const T *)prev;
    size_t count = bytes / sizeof(T), total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        bool 命中 = false;
        switch (操作) {
            case 增加了:     命中 = c[i] > p[i]; break;
            case 减少了:     命中 = c[i] < p[i]; break;
            case 增加了多少: 命中 = ((int64_t)c[i] - (int64_t)p[i]) == (int64_t)阈值; break;
            case 减少了多少: 命中 = ((int64_t)p[i] - (int64_t)c[i]) == (int64_t)阈值; break;
            default: break;
        }
        if (!命中) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * sizeof(T), c + i, sizeof(T));
        n++;
    }
    if (n) { 提交(ctx, out, n); total += n; }
    return total;
}

template <typename T>
static size_t 增减_浮点(const uint8_t *cur, const uint8_t *prev, size_t bytes, uint64_t base,
                        对比类型 操作, T 阈值, AddressValuePair *out, size_t cap,
                        扫描提交 提交, void *ctx) {
    const T *c = (const T *)cur;
    const T *p = (const T *)prev;
    const T 误差 = (T)0.0001;
    size_t count = bytes / sizeof(T), total = 0, n = 0;
    for (size_t i = 0; i < count; i++) {
        bool 命中 = false;
        switch (操作) {
            case 增加了:     命中 = c[i] > p[i]; break;
            case 减少了:     命中 = c[i] < p[i]; break;
            case 增加了多少: 命中 = fabs((double)((c[i] - p[i]) - 阈值)) < (double)误差; break;
            case 减少了多少: 命中 = fabs((double)((p[i] - c[i]) - 阈值)) < (double)误差; break;
            default: break;
        }
        if (!命中) continue;
        if (n == cap) { 提交(ctx, out, n); total += n; n = 0; }
        记一条(out, n, base + (uint64_t)i * sizeof(T), c + i, sizeof(T));
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
    memcpy(&阈值, 目标->bytes, sizeof(T));
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
    memcpy(&阈值, 目标->bytes, sizeof(T));
    return 增减_浮点<T>(cur, prev, bytes, base, 操作, 阈值, out, cap, 提交, ctx);
}

} // namespace

size_t 扫描块_单值(const uint8_t *当前, size_t 字节数, uint64_t 基址,
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
                    (uint8_t)(目标->range_i.min & 0xFF), (uint8_t)(目标->range_i.max & 0xFF),
                    暂存, 暂存容量, 提交, 上下文);
            case 类型_短整数:
                return 区间扫描<int16_t>(当前, 字节数, 基址,
                    (int16_t)目标->range_i.min, (int16_t)目标->range_i.max,
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

size_t 扫描块_双值(const uint8_t *当前, const uint8_t *旧值, size_t 字节数, uint64_t 基址,
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