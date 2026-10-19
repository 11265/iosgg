// 纯 C++17 核心的主机侧回归测试。
//
// 只依赖三个核心的实现文件与 C ABI 头，不涉及 iOS SDK / Theos。
// 编译命令见 Tests/run_tests.sh。

#include "Modules/Scanner/ScannerKernel.h"
#include "Modules/Scanner/SignatureScanner.h"
#include "Core/Algorithms/SSPointerChainCore.h"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

static int g_failures = 0;

#define CHECK(cond)                                                           \
    do {                                                                      \
        if (!(cond)) {                                                        \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            g_failures++;                                                     \
        }                                                                     \
    } while (0)

template <typename T>
static 数值 make_value(T value) {
    数值 out{};
    std::memcpy(out.bytes, &value, sizeof(T));
    return out;
}

// ── 扫描批次收集 ─────────────────────────────────────────────

struct Collected {
    std::vector<AddressValuePair> items;
    std::vector<size_t> batches;
};

static void collect_batch(void *context, const AddressValuePair *items, size_t count) {
    Collected *out = static_cast<Collected *>(context);
    out->batches.push_back(count);
    for (size_t i = 0; i < count; i++) {
        out->items.push_back(items[i]);
    }
}

static std::vector<uint64_t> addresses_of(const Collected &collected) {
    std::vector<uint64_t> result;
    result.reserve(collected.items.size());
    for (const auto &item : collected.items) {
        result.push_back(item.address);
    }
    return result;
}

// ── 比较函数 ─────────────────────────────────────────────────

static void test_type_sizes() {
    CHECK(获取类型大小(类型_字节) == 1);
    CHECK(获取类型大小(类型_短整数) == 2);
    CHECK(获取类型大小(类型_整数) == 4);
    CHECK(获取类型大小(类型_长整数) == 8);
    CHECK(获取类型大小(类型_浮点) == 4);
    CHECK(获取类型大小(类型_双精度) == 8);
}

static void test_compare_exact_and_change() {
    uint32_t previous = 10;
    uint32_t current = 10;
    uint32_t target = 10;

    CHECK(比较值(&current, &previous, &target, 类型_整数, 精确));
    CHECK(!比较值(&current, &previous, &target, 类型_整数, 变化));
    CHECK(比较值(&current, &previous, &target, 类型_整数, 不变));

    current = 11;
    CHECK(!比较值(&current, &previous, &target, 类型_整数, 精确));
    CHECK(比较值(&current, &previous, &target, 类型_整数, 变化));
    CHECK(!比较值(&current, &previous, &target, 类型_整数, 不变));

    // 全零不算“不变”
    uint32_t zero = 0;
    CHECK(!比较值(&zero, &zero, &zero, 类型_整数, 不变));

    // 没有旧值时，依赖旧值的比较一律 false
    CHECK(!比较值(&current, nullptr, &target, 类型_整数, 变化));
    CHECK(!比较值(&current, nullptr, &target, 类型_整数, 增加了));
}

static void test_compare_numeric() {
    uint8_t prev8 = 10, cur8 = 15, delta8 = 5;
    CHECK(比较值(&cur8, &prev8, &delta8, 类型_字节, 增加了));
    CHECK(比较值(&cur8, &prev8, &delta8, 类型_字节, 增加了多少));
    CHECK(!比较值(&cur8, &prev8, &delta8, 类型_字节, 减少了));

    int32_t prev32 = 100, cur32 = 80, delta32 = 20;
    CHECK(比较值(&cur32, &prev32, &delta32, 类型_整数, 减少了));
    CHECK(比较值(&cur32, &prev32, &delta32, 类型_整数, 减少了多少));

    float prevf = 1.0f, curf = 2.5f, deltaf = 1.5f;
    CHECK(比较值(&curf, &prevf, &deltaf, 类型_浮点, 增加了多少));

    double prevd = 10.0, curd = 10.5, deltad = 0.5;
    CHECK(比较值(&curd, &prevd, &deltad, 类型_双精度, 增加了多少));
}

static void test_compare_range() {
    数值 range{};
    range.range_i.min = -2;
    range.range_i.max = 10;

    int32_t inside = 5;
    int32_t outside = 11;
    CHECK(比较值(&inside, nullptr, &range, 类型_整数, 区间));
    CHECK(!比较值(&outside, nullptr, &range, 类型_整数, 区间));

    // 无符号字节区间
    数值 byte_range{};
    byte_range.range_i.min = 250;
    byte_range.range_i.max = 255;
    uint8_t byte_value = 252;
    CHECK(比较值(&byte_value, nullptr, &byte_range, 类型_字节, 区间));

    // 浮点区间
    数值 float_range{};
    float_range.range_f.min = 1.0f;
    float_range.range_f.max = 2.0f;
    float float_value = 1.5f;
    CHECK(比较值(&float_value, nullptr, &float_range, 类型_浮点, 区间));
}

// ── 分块扫描 ─────────────────────────────────────────────────

static void test_block_exact_u8() {
    const uint8_t buffer[] = {1, 2, 1, 3, 1};
    AddressValuePair scratch[2];
    Collected collected;

    数值 target = make_value<uint8_t>(1);
    const size_t total = 扫描块_单值(buffer, sizeof(buffer), 0x1000,
                                     类型_字节, 精确, &target,
                                     scratch, 2, collect_batch, &collected);

    CHECK(total == 3);
    const auto addresses = addresses_of(collected);
    CHECK(addresses.size() == 3);
    CHECK(addresses[0] == 0x1000);
    CHECK(addresses[1] == 0x1002);
    CHECK(addresses[2] == 0x1004);
    CHECK(collected.batches.size() == 2);   // 2 条 + 1 条
}

static void test_block_exact_u32() {
    const uint32_t values[] = {0x11111111u, 0x22222222u, 0x11111111u};
    AddressValuePair scratch[8];
    Collected collected;

    数值 target = make_value<uint32_t>(0x11111111u);
    const size_t total = 扫描块_单值(reinterpret_cast<const uint8_t *>(values), sizeof(values), 0x2000,
                                     类型_整数, 精确, &target,
                                     scratch, 8, collect_batch, &collected);

    CHECK(total == 2);
    const auto addresses = addresses_of(collected);
    CHECK(addresses.size() == 2);
    CHECK(addresses[0] == 0x2000);
    CHECK(addresses[1] == 0x2008);
}

static void test_block_exact_u64() {
    const uint64_t values[] = {0x1122334455667788ULL, 0x99AABBCCDDEEFF00ULL};
    AddressValuePair scratch[8];
    Collected collected;

    数值 target = make_value<uint64_t>(0x99AABBCCDDEEFF00ULL);
    const size_t total = 扫描块_单值(reinterpret_cast<const uint8_t *>(values), sizeof(values), 0x3000,
                                     类型_长整数, 精确, &target,
                                     scratch, 8, collect_batch, &collected);

    CHECK(total == 1);
    const auto addresses = addresses_of(collected);
    CHECK(addresses.size() == 1 && addresses[0] == 0x3008);
}

static void test_block_range() {
    const int32_t values[] = {-5, 0, 5, 15};
    AddressValuePair scratch[8];
    Collected collected;

    数值 target{};
    target.range_i.min = -2;
    target.range_i.max = 10;

    const size_t total = 扫描块_单值(reinterpret_cast<const uint8_t *>(values), sizeof(values), 0x4000,
                                     类型_整数, 区间, &target,
                                     scratch, 8, collect_batch, &collected);

    CHECK(total == 2);
    const auto addresses = addresses_of(collected);
    CHECK(addresses.size() == 2);
    CHECK(addresses[0] == 0x4004);
    CHECK(addresses[1] == 0x4008);
}

static void test_block_double_value() {
    const uint8_t current[] = {1, 5, 9, 0};
    const uint8_t previous[] = {1, 4, 9, 0};
    AddressValuePair scratch[8];

    数值 no_target{};

    {
        Collected collected;
        const size_t total = 扫描块_双值(current, previous, sizeof(current), 0x5000,
                                         类型_字节, 变化, &no_target,
                                         scratch, 8, collect_batch, &collected);
        CHECK(total == 1);
        const auto addresses = addresses_of(collected);
        CHECK(addresses.size() == 1 && addresses[0] == 0x5001);
    }

    {
        Collected collected;
        const size_t total = 扫描块_双值(current, previous, sizeof(current), 0x5000,
                                         类型_字节, 不变, &no_target,
                                         scratch, 8, collect_batch, &collected);
        CHECK(total == 2);   // 1 和 9；全零的 0 不算
        const auto addresses = addresses_of(collected);
        CHECK(addresses.size() == 2);
        CHECK(addresses[0] == 0x5000);
        CHECK(addresses[1] == 0x5002);
    }

    {
        Collected collected;
        数值 delta = make_value<uint8_t>(1);
        const size_t total = 扫描块_双值(current, previous, sizeof(current), 0x5000,
                                         类型_字节, 增加了多少, &delta,
                                         scratch, 8, collect_batch, &collected);
        CHECK(total == 1);
        const auto addresses = addresses_of(collected);
        CHECK(addresses.size() == 1 && addresses[0] == 0x5001);
    }
}

// ── 特征码 ───────────────────────────────────────────────────

static void test_signature_parse() {
    SearchPattern *pattern = 解析特征码("48 8B ?? 00");
    CHECK(pattern != nullptr);
    if (pattern) {
        CHECK(pattern->length == 4);
        CHECK(pattern->bytes[0].byte == 0x48 && !pattern->bytes[0].is_wildcard);
        CHECK(pattern->bytes[1].byte == 0x8B && !pattern->bytes[1].is_wildcard);
        CHECK(pattern->bytes[2].is_wildcard);
        CHECK(pattern->bytes[3].byte == 0x00 && !pattern->bytes[3].is_wildcard);
        释放特征码(pattern);
    }

    pattern = 解析特征码("  48  8b  ??  00 ");
    CHECK(pattern != nullptr);
    if (pattern) {
        CHECK(pattern->length == 4);
        释放特征码(pattern);
    }

    CHECK(解析特征码("ZZ") == nullptr);

    pattern = 解析特征码("");
    CHECK(pattern != nullptr);
    if (pattern) {
        CHECK(pattern->length == 0);
        释放特征码(pattern);
    }
}

static void test_signature_scan() {
    const uint8_t buffer[] = {
        0x48, 0x8B, 0x11, 0x00,
        0x48, 0x8B, 0x22, 0x00,
        0x90
    };

    SearchPattern *pattern = 解析特征码("48 8B ?? 00");
    CHECK(pattern != nullptr);
    if (!pattern) return;

    std::vector<uint64_t> hits;
    const size_t total = 扫描特征码缓冲区(pattern, buffer, sizeof(buffer), 0x1000,
                                         [](void *context, uint64_t address) {
                                             static_cast<std::vector<uint64_t> *>(context)->push_back(address);
                                         },
                                         &hits);

    CHECK(total == 2);
    CHECK(hits.size() == 2);
    CHECK(hits[0] == 0x1000);
    CHECK(hits[1] == 0x1004);

    释放特征码(pattern);
}

// ── 指针链 ───────────────────────────────────────────────────

static void test_chain_parse() {
    SSChainStep steps[SS_CHAIN_MAX_STEPS];
    int code = 0;
    char error[SS_CHAIN_ERROR_MAX] = {0};

    size_t count = ss_chain_parse("[pvz+0x100] -> +0x20 -> +0x30", steps, SS_CHAIN_MAX_STEPS,
                                  nullptr, nullptr, &code, error, sizeof(error));
    CHECK(count == 3);
    CHECK(code == 0);
    CHECK(steps[0].type == SS_CHAIN_STEP_MODULE);
    CHECK(steps[0].offset == 0x100);
    CHECK(std::string(steps[0].module) == "pvz");
    CHECK(steps[1].type == SS_CHAIN_STEP_POINTER && steps[1].offset == 0x20);
    CHECK(steps[2].type == SS_CHAIN_STEP_POINTER && steps[2].offset == 0x30);

    count = ss_chain_parse("[PVZ+100]", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    CHECK(count == 1);
    CHECK(steps[0].type == SS_CHAIN_STEP_MODULE);
    CHECK(steps[0].offset == 0x100);
    CHECK(std::string(steps[0].module) == "pvz");

    count = ss_chain_parse("[pvz]", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    CHECK(count == 1);
    CHECK(steps[0].offset == 0 && std::string(steps[0].module) == "pvz");

    count = ss_chain_parse("0x1000 + 20 + 0x30", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    CHECK(count == 3);
    CHECK(steps[0].type == SS_CHAIN_STEP_ADDRESS && steps[0].offset == 0x1000);
    CHECK(steps[1].type == SS_CHAIN_STEP_POINTER && steps[1].offset == 0x20);
    CHECK(steps[2].type == SS_CHAIN_STEP_POINTER && steps[2].offset == 0x30);

    count = ss_chain_parse("pvz+1a2b", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    CHECK(count == 1);
    CHECK(steps[0].type == SS_CHAIN_STEP_MODULE && steps[0].offset == 0x1a2b);

    count = ss_chain_parse("pvz", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    CHECK(count == 1);
    CHECK(steps[0].type == SS_CHAIN_STEP_MODULE && steps[0].offset == 0);

    count = ss_chain_parse("[pvz+0x10],+0x20", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    CHECK(count == 2);
    CHECK(steps[0].type == SS_CHAIN_STEP_MODULE && steps[0].offset == 0x10);
    CHECK(steps[1].type == SS_CHAIN_STEP_POINTER && steps[1].offset == 0x20);

    count = ss_chain_parse("", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    CHECK(count == 0);
    CHECK(code == -1);
    CHECK(std::strlen(error) > 0);

    count = ss_chain_parse("[pvz+0x1", steps, SS_CHAIN_MAX_STEPS, nullptr, nullptr,
                           &code, error, sizeof(error));
    // 缺少右括号：按“无 + 的模块名”处理，与原实现一致
    CHECK(count == 1);
    CHECK(steps[0].type == SS_CHAIN_STEP_MODULE);
}

static std::unordered_map<uint64_t, uint64_t> g_fake_memory;

static int fake_read(uint64_t address, uint64_t *value, void *context) {
    (void)context;
    const auto it = g_fake_memory.find(address);
    if (it == g_fake_memory.end()) return 1;   // 非 0 即错误
    *value = it->second;
    return 0;
}

struct LogSink {
    std::string text;
};

static void collect_log(const char *message, void *context) {
    static_cast<LogSink *>(context)->text += message;
    static_cast<LogSink *>(context)->text += "\n";
}

static void test_chain_resolve() {
    g_fake_memory.clear();
    g_fake_memory[0x1100] = 0x2000;
    g_fake_memory[0x2020] = 0x3000;

    SSChainStep steps[3] = {};
    steps[0].type = SS_CHAIN_STEP_MODULE;
    steps[0].offset = 0x100;
    steps[1].type = SS_CHAIN_STEP_POINTER;
    steps[1].offset = 0x20;
    steps[2].type = SS_CHAIN_STEP_POINTER;
    steps[2].offset = 0x8;

    int status = 99;
    char error[SS_CHAIN_ERROR_MAX] = {0};
    LogSink sink;

    const uint64_t result = ss_chain_resolve(steps, 3, 0x1000, fake_read, collect_log, &sink,
                                             &status, error, sizeof(error));
    CHECK(status == 0);
    CHECK(result == 0x3008);
    CHECK(sink.text.find("最终地址: 0x3008") != std::string::npos);

    // 读失败：第二个指针的地址不在假内存里
    g_fake_memory.erase(0x2020);
    status = 0;
    const uint64_t failed = ss_chain_resolve(steps, 3, 0x1000, fake_read, nullptr, nullptr,
                                             &status, error, sizeof(error));
    CHECK(failed == 0);
    CHECK(status != 0);
    CHECK(std::strlen(error) > 0);

    // 空链
    status = 0;
    CHECK(ss_chain_resolve(nullptr, 0, 0, fake_read, nullptr, nullptr,
                           &status, error, sizeof(error)) == 0);
    CHECK(status == -1);
}

static void test_chain_parse_then_resolve() {
    g_fake_memory.clear();
    g_fake_memory[0x1100] = 0x2000;

    SSChainStep steps[SS_CHAIN_MAX_STEPS];
    int code = 0;
    char error[SS_CHAIN_ERROR_MAX] = {0};
    const size_t count = ss_chain_parse("[mod+0x100] -> +0x20", steps, SS_CHAIN_MAX_STEPS,
                                        nullptr, nullptr, &code, error, sizeof(error));
    CHECK(count == 2);

    int status = 0;
    const uint64_t result = ss_chain_resolve(steps, count, 0x1000, fake_read, nullptr, nullptr,
                                             &status, error, sizeof(error));
    CHECK(status == 0);
    CHECK(result == 0x2020);
}

int main() {
    test_type_sizes();
    test_compare_exact_and_change();
    test_compare_numeric();
    test_compare_range();
    test_block_exact_u8();
    test_block_exact_u32();
    test_block_exact_u64();
    test_block_range();
    test_block_double_value();
    test_signature_parse();
    test_signature_scan();
    test_chain_parse();
    test_chain_resolve();
    test_chain_parse_then_resolve();

    if (g_failures == 0) {
        std::printf("All core engine tests passed.\n");
        return 0;
    }

    std::fprintf(stderr, "%d core engine test(s) failed.\n", g_failures);
    return 1;
}
