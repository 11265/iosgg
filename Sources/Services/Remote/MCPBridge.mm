//
//  MCPBridge.mm
//  进程内调试桥：一行一个 JSON 请求，一行一个 JSON 响应。
//
//  请求：  {"id":1,"token":"igg-mcp-27801","cmd":"read_memory","args":{"address":"0x1000","size":64}}
//  响应：  {"id":1,"ok":true,"result":{...}}
//          {"id":1,"ok":false,"error":"..."}
//
//  注意：
//   * 地址一律用十六进制字符串（JSON 数字超过 2^53 会丢精度）。
//   * 命中（观察点/执行断点）会被记录进一个环形缓冲，AI 通过 recent_hits 轮询取用
//     —— AI 无法被"推送"通知，只能主动拉取。
//   * 所有内存读写都在本进程内完成（内嵌调试器），不需要 task_for_pid。
//

#import "Services/Remote/MCPBridge.h"
#import "Services/LogService.h"
#import "Services/Debugger/SSDebugger.h"
#import "Services/Memory/ARM64Assembler.h"
#import "Constants/NotificationNames.h"
#import "Services/Debugger/DynaDbg/core/native_api.h"

#import <arpa/inet.h>
#import <errno.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <netinet/in.h>
#import <pthread.h>
#import <sys/socket.h>
#import <unistd.h>

extern "C" mach_port_t get_cached_task_port(pid_t pid);

#define kSSMCPDefaultPort       27801
#define kSSMCPToken             @"igg-mcp-27801"
#define kSSMCPMaxHits           200
#define kSSMCPMaxReadSize       (256 * 1024)
#define kSSMCPMaxSearchResults  20000
#define kSSMCPMaxSearchRegion   (256ULL * 1024 * 1024)

#pragma mark - 小工具

static NSString *HexString(uint64_t value) {
    return [NSString stringWithFormat:@"0x%llX", value];
}

static uint64_t ParseAddress(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return strtoull([(NSString *)value UTF8String], NULL, 16);
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value unsignedLongLongValue];
    }
    return 0;
}

static NSData *ParseHexData(NSString *hex) {
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger i = 0; i < hex.length; i++) {
        unichar c = [hex characterAtIndex:i];
        if (isxdigit((int)c)) {
            [clean appendFormat:@"%C", c];
        }
    }
    if (clean.length == 0 || (clean.length % 2) != 0) {
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithCapacity:clean.length / 2];
    for (NSUInteger i = 0; i < clean.length; i += 2) {
        unsigned int byte = 0;
        [[NSScanner scannerWithString:[clean substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

static NSString *ProtectionString(vm_prot_t prot) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:(prot & VM_PROT_READ) ? @"r" : @"-"];
    [s appendString:(prot & VM_PROT_WRITE) ? @"w" : @"-"];
    [s appendString:(prot & VM_PROT_EXECUTE) ? @"x" : @"-"];
    return s;
}

/// 遍历本进程 VM 区域（含路径，便于判断是哪个模块/堆/栈）
static void EnumerateRegions(void (^block)(uint64_t start, uint64_t end, vm_prot_t prot, const char *path)) {
    mach_vm_address_t address = 0;
    while (true) {
        mach_vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t objectName = MACH_PORT_NULL;
        memset(&info, 0, sizeof(info));

        kern_return_t kr = mach_vm_region(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64,
                                          (vm_region_info_t)&info, &count, &objectName);
        if (objectName != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), objectName);
        }
        if (kr != KERN_SUCCESS || size == 0) {
            break;
        }

        char path[256] = {0};
        if (g_proc_regionfilename) {
            g_proc_regionfilename(getpid(), address, path, sizeof(path));
        }

        block((uint64_t)address, (uint64_t)address + (uint64_t)size, info.protection, path);

        mach_vm_address_t next = address + size;
        if (next <= address) {
            break;
        }
        address = next;
    }
}

/// 模块范围（用 dyld 拿，避免和 native_api.h 里的 C 结构体 ModuleInfo 撞名）
static NSArray<NSDictionary *> *EnumerateModules(void) {
    NSMutableArray<NSDictionary *> *modules = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!header) {
            continue;
        }
        uint64_t slide = (uint64_t)_dyld_get_image_vmaddr_slide(i);
        uint64_t minAddress = UINT64_MAX;
        uint64_t maxAddress = 0;

        const struct load_command *cmd = (const struct load_command *)(header + 1);
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)cmd;
                uint64_t start = seg->vmaddr + slide;
                uint64_t end = start + seg->vmsize;
                if (start < minAddress) minAddress = start;
                if (end > maxAddress) maxAddress = end;
            }
            cmd = (const struct load_command *)((const uintptr_t)cmd + cmd->cmdsize);
        }
        if (maxAddress <= minAddress) {
            continue;
        }

        const char *name = _dyld_get_image_name(i);
        [modules addObject:@{
            @"name": name ? [NSString stringWithUTF8String:name].lastPathComponent : @"",
            @"path": name ? [NSString stringWithUTF8String:name] : @"",
            @"base": HexString(minAddress),
            @"end": HexString(maxAddress),
            @"size": @(maxAddress - minAddress),
        }];
    }
    return modules;
}

#pragma mark - 桥本体

@interface SSMCPBridge () {
    pthread_mutex_t _lock;
    int _listenFD;
}

@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) BOOL running;

/// 命中环形缓冲（最近的在最前）
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *hits;
/// 搜索会话
@property (nonatomic, strong) NSMutableArray<NSNumber *> *searchAddresses;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *searchValues;
@property (nonatomic, assign) NSUInteger searchWidth;

@end

@implementation SSMCPBridge

+ (instancetype)sharedInstance {
    static SSMCPBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSMCPBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _listenFD = -1;
        _hits = [NSMutableArray array];
        _searchAddresses = [NSMutableArray array];
        _searchValues = [NSMutableArray array];
        pthread_mutex_init(&_lock, NULL);

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recordWatchpointHit:)
                                                     name:kSSDebuggerDidHitWatchpointNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recordBreakpointHit:)
                                                     name:kSSDebuggerDidHitBreakpointNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    pthread_mutex_destroy(&_lock);
}

#pragma mark - 生命周期

- (BOOL)startOnPort:(uint16_t)port {
    if (self.running) {
        return YES;
    }
    if (port == 0) {
        port = kSSMCPDefaultPort;
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        [LoggingService log:@"[MCP] socket() 失败: errno=%d", errno];
        return NO;
    }

    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        [LoggingService log:@"[MCP] bind(%u) 失败: errno=%d（端口被占用？）", port, errno];
        close(fd);
        return NO;
    }
    if (listen(fd, 4) != 0) {
        [LoggingService log:@"[MCP] listen 失败: errno=%d", errno];
        close(fd);
        return NO;
    }

    _listenFD = fd;
    self.port = port;
    self.running = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self acceptLoop];
    });

    [LoggingService log:@"[MCP] 调试桥已监听 0.0.0.0:%u（PC 侧 MCP 服务器连过来即可）", port];
    return YES;
}

- (void)stop {
    if (!self.running) {
        return;
    }
    self.running = NO;
    if (_listenFD >= 0) {
        close(_listenFD);
        _listenFD = -1;
    }
    [LoggingService log:@"[MCP] 调试桥已停止"];
}

- (void)acceptLoop {
    while (self.running && _listenFD >= 0) {
        struct sockaddr_in peer;
        socklen_t peerLen = sizeof(peer);
        int client = accept(_listenFD, (struct sockaddr *)&peer, &peerLen);
        if (client < 0) {
            if (!self.running) {
                break;
            }
            usleep(50 * 1000);
            continue;
        }

        char peerText[INET_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET, &peer.sin_addr, peerText, sizeof(peerText));
        [LoggingService log:@"[MCP] 客户端接入: %s:%u", peerText, ntohs(peer.sin_port)];

        // 串行处理（AI 的调用是一条一条来的），处理完再接受下一个
        [self serveClient:client];
        close(client);
        [LoggingService log:@"[MCP] 客户端断开"];
    }
}

- (void)serveClient:(int)client {
    NSMutableData *buffer = [NSMutableData data];

    while (self.running) {
        uint8_t chunk[8192];
        ssize_t n = recv(client, chunk, sizeof(chunk), 0);
        if (n <= 0) {
            return;
        }
        [buffer appendBytes:chunk length:(NSUInteger)n];

        // 按行拆分
        while (true) {
            const uint8_t *bytes = (const uint8_t *)buffer.bytes;
            NSUInteger length = buffer.length;
            NSUInteger newline = NSNotFound;
            for (NSUInteger i = 0; i < length; i++) {
                if (bytes[i] == '\n') {
                    newline = i;
                    break;
                }
            }
            if (newline == NSNotFound) {
                break;
            }

            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, newline)];
            [buffer replaceBytesInRange:NSMakeRange(0, newline + 1) withBytes:NULL length:0];

            NSDictionary *response = [self handleRequestData:lineData];
            NSData *payload = [NSJSONSerialization dataWithJSONObject:response options:0 error:NULL];
            if (!payload) {
                continue;
            }
            NSMutableData *out = [NSMutableData dataWithData:payload];
            uint8_t nl = '\n';
            [out appendBytes:&nl length:1];

            const uint8_t *outBytes = (const uint8_t *)out.bytes;
            NSUInteger remaining = out.length;
            while (remaining > 0) {
                ssize_t sent = send(client, outBytes, remaining, 0);
                if (sent <= 0) {
                    return;
                }
                outBytes += sent;
                remaining -= (NSUInteger)sent;
            }
        }
    }
}

#pragma mark - 请求处理

- (NSDictionary *)handleRequestData:(NSData *)data {
    NSError *jsonError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        return @{@"id": @0, @"ok": @NO, @"error": @"请求不是合法 JSON 对象"};
    }
    NSDictionary *request = (NSDictionary *)parsed;
    id requestId = request[@"id"] ?: @0;
    NSString *cmd = request[@"cmd"];
    NSDictionary *args = [request[@"args"] isKindOfClass:[NSDictionary class]] ? request[@"args"] : @{};

    if (![cmd isKindOfClass:[NSString class]] || cmd.length == 0) {
        return @{@"id": requestId, @"ok": @NO, @"error": @"缺少 cmd"};
    }

    // 简单口令：挡住同网段的随手扫描（不是密码学意义上的认证）
    if (![kSSMCPToken isEqualToString:request[@"token"] ?: @""]) {
        return @{@"id": requestId, @"ok": @NO, @"error": @"token 不正确"};
    }

    NSString *error = nil;
    NSDictionary *result = [self executeCommand:cmd args:args error:&error];
    if (error) {
        return @{@"id": requestId, @"ok": @NO, @"error": error};
    }
    return @{@"id": requestId, @"ok": @YES, @"result": result ?: @{}};
}

- (NSDictionary *)executeCommand:(NSString *)cmd args:(NSDictionary *)args error:(NSString **)error {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    pid_t pid = getpid();

    // ---- 基础 ----
    if ([cmd isEqualToString:@"ping"]) {
        return @{@"pong": @YES, @"pid": @(pid), @"port": @(self.port)};
    }

    if ([cmd isEqualToString:@"status"]) {
        NSMutableArray *watchpoints = [NSMutableArray array];
        NSDictionary<NSNumber *, NSNumber *> *watched = [debugger getAllWatchedAddresses];
        for (NSNumber *address in watched) {
            [watchpoints addObject:@{
                @"address": HexString([address unsignedLongLongValue]),
                @"type": watched[address],
            }];
        }
        return @{
            @"pid": @(pid),
            @"processName": [NSProcessInfo processInfo].processName ?: @"",
            @"debugging": @(debugger.isDebugging),
            @"bridgePort": @(self.port),
            @"watchpoints": watchpoints,
            @"functionBreakpoints": [debugger functionBreakpoints] ?: @[],
            @"breakpointStopsExecution": @(debugger.breakpointStopsExecution),
            @"lastCallStack": [debugger lastCallStack] ?: @[],
        };
    }

    if ([cmd isEqualToString:@"list_modules"]) {
        return @{@"modules": EnumerateModules()};
    }

    if ([cmd isEqualToString:@"memory_regions"]) {
        NSUInteger max = [args[@"max"] unsignedIntegerValue] ?: 200;
        NSMutableArray *regions = [NSMutableArray array];
        EnumerateRegions(^(uint64_t start, uint64_t end, vm_prot_t prot, const char *path) {
            if (regions.count >= max) {
                return;
            }
            [regions addObject:@{
                @"start": HexString(start),
                @"end": HexString(end),
                @"size": @(end - start),
                @"protection": ProtectionString(prot),
                @"path": path[0] ? [NSString stringWithUTF8String:path] : @"",
            }];
        });
        return @{@"regions": regions, @"count": @(regions.count)};
    }

    // ---- 内存 ----
    if ([cmd isEqualToString:@"read_memory"]) {
        uint64_t address = ParseAddress(args[@"address"]);
        NSUInteger size = [args[@"size"] unsignedIntegerValue] ?: 64;
        size = MIN(size, (NSUInteger)kSSMCPMaxReadSize);
        if (address == 0 || size == 0) {
            *error = @"address/size 不合法";
            return nil;
        }

        unsigned char *buffer = (unsigned char *)malloc(size);
        if (!buffer) {
            *error = @"内存分配失败";
            return nil;
        }
        ssize_t read = read_memory_native(pid, address, size, buffer);
        if (read <= 0) {
            free(buffer);
            *error = [NSString stringWithFormat:@"读取失败: %@", HexString(address)];
            return nil;
        }
        NSMutableString *hex = [NSMutableString stringWithCapacity:(NSUInteger)read * 2];
        for (ssize_t i = 0; i < read; i++) {
            [hex appendFormat:@"%02x", buffer[i]];
        }
        free(buffer);
        return @{@"address": HexString(address), @"size": @(read), @"hex": hex};
    }

    if ([cmd isEqualToString:@"write_memory"]) {
        uint64_t address = ParseAddress(args[@"address"]);
        NSString *hex = args[@"hex"];
        NSData *data = [hex isKindOfClass:[NSString class]] ? ParseHexData(hex) : nil;
        if (address == 0 || data.length == 0) {
            *error = @"address/hex 不合法";
            return nil;
        }
        ssize_t written = write_memory_native(pid, address, data.length, (unsigned char *)data.bytes);
        if (written <= 0) {
            *error = @"写入失败（页面可能不可写）";
            return nil;
        }
        return @{@"address": HexString(address), @"written": @(written)};
    }

    if ([cmd isEqualToString:@"disassemble"]) {
        uint64_t address = ParseAddress(args[@"address"]);
        NSUInteger count = [args[@"count"] unsignedIntegerValue] ?: 10;
        count = MIN(count, 200);
        if (address == 0 || count == 0) {
            *error = @"address/count 不合法";
            return nil;
        }

        NSMutableArray *instructions = [NSMutableArray array];
        for (NSUInteger i = 0; i < count; i++) {
            uint64_t current = address + i * 4;
            uint32_t instruction = 0;
            if (read_memory_native(pid, current, 4, (unsigned char *)&instruction) != 4) {
                break;
            }
            DisassembledInstruction *disassembled = [ARM64Assembler disassemble:instruction atAddress:current];
            [instructions addObject:@{
                @"address": HexString(current),
                @"word": [NSString stringWithFormat:@"0x%08X", instruction],
                @"text": disassembled ? [NSString stringWithFormat:@"%@ %@",
                                          disassembled.mnemonic ?: @"?", disassembled.opStr ?: @""] : @"?",
                @"isBranchLink": @(disassembled.isBranchLink),
                @"target": HexString(disassembled.targetAddress),
            }];
        }
        return @{@"instructions": instructions};
    }

    // ---- 符号 ----
    if ([cmd isEqualToString:@"list_symbols"]) {
        uint64_t base = ParseAddress(args[@"moduleBase"]);
        NSString *moduleName = args[@"module"];
        if (base == 0 && [moduleName isKindOfClass:[NSString class]] && moduleName.length > 0) {
            for (NSDictionary *module in EnumerateModules()) {
                if ([module[@"name"] isEqualToString:moduleName] ||
                    [module[@"path"] hasSuffix:moduleName]) {
                    base = ParseAddress(module[@"base"]);
                    break;
                }
            }
        }
        if (base == 0) {
            *error = @"需要 moduleBase 或 module";
            return nil;
        }

        size_t symbolCount = 0;
        SymbolInfo *symbols = enumerate_symbols(pid, base, &symbolCount);
        if (!symbols) {
            return @{@"symbols": @[], @"count": @0};
        }

        NSString *filter = [args[@"filter"] isKindOfClass:[NSString class]] ? args[@"filter"] : nil;
        NSUInteger max = [args[@"max"] unsignedIntegerValue] ?: 200;
        max = MIN(max, 2000);

        NSMutableArray *result = [NSMutableArray array];
        for (size_t i = 0; i < symbolCount && result.count < max; i++) {
            NSString *name = symbols[i].name ? [NSString stringWithUTF8String:symbols[i].name] : @"";
            if (filter.length > 0 && ![name containsString:filter]) {
                continue;
            }
            [result addObject:@{
                @"name": name,
                @"address": HexString(symbols[i].address),
                @"moduleBase": HexString(symbols[i].module_base),
            }];
        }

        for (size_t i = 0; i < symbolCount; i++) {
            free(symbols[i].name);
            free(symbols[i].type);
            free(symbols[i].scope);
            free(symbols[i].file_name);
        }
        free(symbols);

        return @{@"symbols": result, @"count": @(result.count), @"totalSymbols": @(symbolCount)};
    }

    // ---- 调试器：观察点 ----
    if ([cmd isEqualToString:@"set_watchpoint"]) {
        uint64_t address = ParseAddress(args[@"address"]);
        NSUInteger size = [args[@"size"] unsignedIntegerValue] ?: 4;
        NSString *type = [args[@"type"] isKindOfClass:[NSString class]] ? args[@"type"] : @"write";
        if (address == 0) {
            *error = @"address 不合法";
            return nil;
        }

        [self ensureDebugging];

        SSBreakpointType breakpointType = SSBreakpointTypeWrite;
        if ([type isEqualToString:@"read"]) {
            breakpointType = SSBreakpointTypeRead;
        } else if ([type isEqualToString:@"readwrite"] || [type isEqualToString:@"rw"]) {
            breakpointType = SSBreakpointTypeReadWrite;
        }

        NSError *watchError = nil;
        BOOL ok = [debugger watchAddress:address size:size type:breakpointType callback:nil error:&watchError];
        if (!ok) {
            *error = watchError.localizedDescription ?: @"设置观察点失败";
            return nil;
        }
        return @{@"address": HexString(address), @"size": @(size), @"type": type};
    }

    if ([cmd isEqualToString:@"remove_watchpoint"]) {
        uint64_t address = ParseAddress(args[@"address"]);
        [debugger removeWatchAtAddress:address];
        return @{@"address": HexString(address), @"removed": @YES};
    }

    if ([cmd isEqualToString:@"list_watchpoints"]) {
        NSDictionary<NSNumber *, NSNumber *> *watched = [debugger getAllWatchedAddresses];
        NSMutableArray *result = [NSMutableArray array];
        for (NSNumber *address in watched) {
            [result addObject:@{@"address": HexString([address unsignedLongLongValue]),
                                @"type": watched[address]}];
        }
        return @{@"watchpoints": result};
    }

    // ---- 调试器：执行断点 ----
    if ([cmd isEqualToString:@"set_function_breakpoint"]) {
        uint64_t address = ParseAddress(args[@"address"]);
        BOOL software = args[@"software"] ? [args[@"software"] boolValue] : YES;
        BOOL stopExecution = args[@"stopExecution"] ? [args[@"stopExecution"] boolValue] : NO;
        int hitCount = args[@"hitCount"] ? [args[@"hitCount"] intValue] : 0;
        if (address == 0) {
            *error = @"address 不合法";
            return nil;
        }

        [self ensureDebugging];
        debugger.breakpointStopsExecution = stopExecution;

        if (![debugger setFunctionBreakpoint:address software:software hitCount:hitCount]) {
            *error = software ? @"下软件断点失败（代码页可能不可写）" : @"下硬件断点失败（槽位可能已满）";
            return nil;
        }
        return @{@"address": HexString(address),
                 @"software": @(software),
                 @"stopExecution": @(stopExecution)};
    }

    if ([cmd isEqualToString:@"remove_function_breakpoint"]) {
        uint64_t address = ParseAddress(args[@"address"]);
        [debugger removeFunctionBreakpoint:address];
        return @{@"address": HexString(address), @"removed": @YES};
    }

    if ([cmd isEqualToString:@"list_function_breakpoints"]) {
        return @{@"breakpoints": [debugger functionBreakpoints] ?: @[],
                 @"stopExecution": @(debugger.breakpointStopsExecution)};
    }

    if ([cmd isEqualToString:@"continue_thread"]) {
        BOOL ok = [debugger continueStoppedThread];
        if (!ok) {
            *error = @"没有处于停顿状态的线程";
            return nil;
        }
        return @{@"resumed": @YES};
    }

    if ([cmd isEqualToString:@"call_stack"]) {
        id threadIdValue = args[@"threadId"];
        if (threadIdValue) {
            NSArray<NSString *> *stack = [debugger captureCallStackForThread:ParseAddress(threadIdValue)];
            return @{@"callStack": stack ?: @[]};
        }
        return @{@"callStack": [debugger lastCallStack] ?: @[]};
    }

    // ---- 调试器：命中记录 ----
    if ([cmd isEqualToString:@"recent_hits"]) {
        NSUInteger limit = [args[@"limit"] unsignedIntegerValue] ?: 20;
        NSMutableArray *snapshot = [NSMutableArray array];
        pthread_mutex_lock(&_lock);
        for (NSUInteger i = 0; i < _hits.count && snapshot.count < limit; i++) {
            [snapshot addObject:_hits[i]];
        }
        pthread_mutex_unlock(&_lock);
        return @{@"hits": snapshot, @"total": @(snapshot.count)};
    }

    if ([cmd isEqualToString:@"clear_hits"]) {
        pthread_mutex_lock(&_lock);
        [_hits removeAllObjects];
        pthread_mutex_unlock(&_lock);
        return @{@"cleared": @YES};
    }

    // ---- 搜索 ----
    if ([cmd isEqualToString:@"search_value"]) {
        return [self handleSearchCommand:args refine:NO error:error];
    }
    if ([cmd isEqualToString:@"search_refine"]) {
        return [self handleSearchCommand:args refine:YES error:error];
    }
    if ([cmd isEqualToString:@"clear_search"]) {
        pthread_mutex_lock(&_lock);
        [_searchAddresses removeAllObjects];
        [_searchValues removeAllObjects];
        _searchWidth = 0;
        pthread_mutex_unlock(&_lock);
        return @{@"cleared": @YES};
    }

    // ---- 日志 ----
    if ([cmd isEqualToString:@"log_tail"]) {
        NSUInteger limit = [args[@"limit"] unsignedIntegerValue] ?: 50;
        return @{@"logs": [LoggingService recentLogs:limit] ?: @[]};
    }

    *error = [NSString stringWithFormat:@"未知命令: %@", cmd];
    return nil;
}

- (void)ensureDebugging {
    SSDebugger *debugger = [SSDebugger sharedInstance];
    if (!debugger.isDebugging) {
        [LoggingService log:@"[MCP] 调试器未运行，自动启动 (pid=%d)", getpid()];
        [debugger startDebugWithPid:getpid()];
    }
}

#pragma mark - 命中记录

- (void)appendHit:(NSDictionary *)hit {
    pthread_mutex_lock(&_lock);
    [_hits insertObject:hit atIndex:0];
    while (_hits.count > kSSMCPMaxHits) {
        [_hits removeLastObject];
    }
    pthread_mutex_unlock(&_lock);
}

- (void)recordWatchpointHit:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    [self appendHit:@{
        @"kind": @"watchpoint",
        @"address": HexString([userInfo[@"address"] unsignedLongLongValue]),
        @"pc": HexString([userInfo[@"pc"] unsignedLongLongValue]),
        @"threadId": userInfo[@"threadId"] ?: @0,
        @"value": userInfo[@"value"] ?: @0,
        @"callStack": userInfo[@"callStack"] ?: @[],
        @"registers": [self selectedRegisters:userInfo[@"registers"]],
        @"time": @([[NSDate date] timeIntervalSince1970]),
    }];
}

- (void)recordBreakpointHit:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    NSDictionary *breakpoint = userInfo[@"breakpoint"] ?: @{};
    [self appendHit:@{
        @"kind": @"breakpoint",
        @"address": HexString([userInfo[@"address"] unsignedLongLongValue]),
        @"pc": HexString([userInfo[@"pc"] unsignedLongLongValue]),
        @"threadId": userInfo[@"threadId"] ?: @0,
        @"software": breakpoint[@"software"] ?: @NO,
        @"hitCount": breakpoint[@"hitCount"] ?: @0,
        @"stopExecution": userInfo[@"stopExecution"] ?: @NO,
        @"callStack": userInfo[@"callStack"] ?: @[],
        @"registers": [self selectedRegisters:userInfo[@"registers"]],
        @"time": @([[NSDate date] timeIntervalSince1970]),
    }];
}

/// 只保留定位问题最常用的寄存器，避免返回体太大
- (NSDictionary *)selectedRegisters:(NSDictionary *)registers {
    if (![registers isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSMutableDictionary *selected = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"x0", @"x1", @"x2", @"x3", @"x4", @"x5", @"x6", @"x7", @"x8",
                             @"fp", @"lr", @"sp", @"pc"]) {
        if (registers[name]) {
            selected[name] = registers[name];
        }
    }
    return selected;
}

#pragma mark - 搜索（精简版：首次精确扫描 + 变化/未变/新值筛选）

- (NSDictionary *)handleSearchCommand:(NSDictionary *)args refine:(BOOL)refine error:(NSString **)error {
    NSString *type = [args[@"type"] isKindOfClass:[NSString class]] ? args[@"type"] : @"u32";
    NSString *valueText = [args[@"value"] isKindOfClass:[NSString class]] ? args[@"value"] : nil;
    NSString *mode = [args[@"mode"] isKindOfClass:[NSString class]] ? args[@"mode"] : @"eq";
    NSUInteger max = [args[@"max"] unsignedIntegerValue] ?: 2000;
    max = MIN(max, (NSUInteger)kSSMCPMaxSearchResults);

    NSUInteger width = 0;
    uint64_t needle = 0;
    if ([type isEqualToString:@"u8"]) width = 1;
    else if ([type isEqualToString:@"u16"]) width = 2;
    else if ([type isEqualToString:@"u32"]) width = 4;
    else if ([type isEqualToString:@"u64"]) width = 8;
    else if ([type isEqualToString:@"f32"]) width = 4;
    else if ([type isEqualToString:@"f64"]) width = 8;
    else {
        *error = @"type 只支持 u8/u16/u32/u64/f32/f64";
        return nil;
    }

    if (refine && mode) {
        // 变化/未变模式不需要 value
    } else if (valueText.length == 0) {
        *error = @"缺少 value";
        return nil;
    }

    BOOL isFloat = [type hasPrefix:@"f"];
    if (isFloat) {
        if (width == 4) {
            float f = strtof([valueText UTF8String], NULL);
            uint32_t bits = 0;
            memcpy(&bits, &f, 4);
            needle = bits;
        } else {
            double d = strtod([valueText UTF8String], NULL);
            memcpy(&needle, &d, 8);
        }
    } else {
        needle = strtoull([valueText UTF8String], NULL, 0);
    }

    pid_t pid = getpid();
    NSMutableArray<NSNumber *> *addresses = [NSMutableArray array];
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];

    if (refine) {
        pthread_mutex_lock(&_lock);
        NSArray<NSNumber *> *previousAddresses = [_searchAddresses copy];
        NSArray<NSNumber *> *previousValues = [_searchValues copy];
        NSUInteger previousWidth = _searchWidth;
        pthread_mutex_unlock(&_lock);

        if (previousWidth != width) {
            *error = @"类型和上次扫描不一致，请重新 search_value";
            return nil;
        }

        for (NSUInteger i = 0; i < previousAddresses.count && addresses.count < max; i++) {
            uint64_t address = [previousAddresses[i] unsignedLongLongValue];
            uint64_t current = 0;
            if (read_memory_native(pid, address, width, (unsigned char *)&current) != (ssize_t)width) {
                continue;
            }
            uint64_t mask = (width == 8) ? ~0ULL : ((1ULL << (width * 8)) - 1);
            current &= mask;
            uint64_t old = [previousValues[i] unsignedLongLongValue] & mask;
            BOOL keep = NO;
            if ([mode isEqualToString:@"changed"]) {
                keep = (current != old);
            } else if ([mode isEqualToString:@"unchanged"]) {
                keep = (current == old);
            } else {
                keep = (current == (needle & mask));
            }
            if (keep) {
                [addresses addObject:@(address)];
                [values addObject:@(current)];
            }
        }
    } else {
        uint64_t mask = (width == 8) ? ~0ULL : ((1ULL << (width * 8)) - 1);
        needle &= mask;
        NSUInteger alignment = (width >= 4) ? 4 : 1;
        const size_t chunkSize = 512 * 1024;

        EnumerateRegions(^(uint64_t start, uint64_t end, vm_prot_t prot, const char *path) {
            if (addresses.count >= max) {
                return;
            }
            if ((prot & VM_PROT_READ) == 0 || (prot & VM_PROT_WRITE) == 0) {
                return;  // 只搜可写数据区
            }
            if (prot & VM_PROT_EXECUTE) {
                return;  // 跳过代码页
            }
            if (end - start > kSSMCPMaxSearchRegion) {
                return;
            }

            unsigned char *buffer = (unsigned char *)malloc(chunkSize);
            if (!buffer) {
                return;
            }

            uint64_t cursor = start;
            while (cursor < end && addresses.count < max) {
                size_t want = (size_t)MIN((uint64_t)chunkSize, end - cursor);
                ssize_t got = read_memory_native(pid, cursor, want, buffer);
                if (got > 0) {
                    for (size_t offset = 0; offset + width <= (size_t)got; offset += alignment) {
                        uint64_t candidate = 0;
                        memcpy(&candidate, buffer + offset, width);
                        candidate &= (width == 8) ? ~0ULL : ((1ULL << (width * 8)) - 1);
                        if (candidate == needle) {
                            [addresses addObject:@(cursor + offset)];
                            [values addObject:@(candidate)];
                            if (addresses.count >= max) {
                                break;
                            }
                        }
                    }
                }
                cursor += want;
            }
            free(buffer);
        });
    }

    pthread_mutex_lock(&_lock);
    [_searchAddresses setArray:addresses];
    [_searchValues setArray:values];
    _searchWidth = width;
    pthread_mutex_unlock(&_lock);

    NSMutableArray *resultAddresses = [NSMutableArray array];
    for (NSNumber *address in addresses) {
        [resultAddresses addObject:HexString([address unsignedLongLongValue])];
    }

    return @{@"addresses": resultAddresses,
             @"count": @(addresses.count),
             @"type": type,
             @"refine": @(refine)};
}

@end
