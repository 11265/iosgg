# iosgg MCP 桥（让 AI/DSH 直接操作这个调试器）

## 架构

```
DSH（Windows） --stdio(JSON-RPC/MCP)--> iosgg_mcp_server.js --TCP(一行一个 JSON)--> 手机游戏进程内的 SSMCPBridge
                        （零依赖 Node）                        192.168.3.11:27801
```

- **设备侧**：tweak 里的 `Sources/Services/Remote/MCPBridge.mm`，只做"一行 JSON 进、一行 JSON 出"，不实现 MCP 协议。
- **PC 侧**：本目录的 `iosgg_mcp_server.js`，把 MCP 的 `tools/list` / `tools/call` 翻译成桥命令。零依赖，只用 Node 内置模块。
- 设备启动日志里会出现 `[MCP] 调试桥已监听 0.0.0.0:27801`。

## 部署（三步）

1. **手机侧**：编译安装 tweak（`make package install`），确保日志里有上面的监听提示。
2. **PC 侧**：把本目录的 js 同步到 Windows 本地目录（DSH 用 Windows 的 node 跑，读不了 WSL 的 UNC 路径）：

   ```bash
   wsl -d Ubuntu-24.04 -- bash -c "mkdir -p /mnt/c/Users/oo/.dsh/mcp/iosgg && cp /home/oo/iosgg/tools/mcp/*.js /mnt/c/Users/oo/.dsh/mcp/iosgg/"
   ```

3. **DSH 侧**：在 `C:\Users\oo\.dsh\profiles\desktop\cordis.patch.yml` 里加一条（已加好则跳过）：

   ```yaml
   - id: mcp-iosgg
     name: "@deepseek-ai/dsh-mcp-client"
     config:
       serverName: iosgg
       transport: stdio
       command: 'C:\Users\oo\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
       args: ['C:\Users\oo\.dsh\mcp\iosgg\iosgg_mcp_server.js']
       env:
         IOSGG_HOST: 192.168.3.11
         IOSGG_PORT: '27801'
       toolCallTimeoutMs: 30000
       failOnStartupError: false
   ```

   工具会以 `mcp__iosgg__<工具名>` 出现在 AI 的工具列表里（如 `mcp__iosgg__iosgg_ping`）。

## 自检

```bash
# 1) 离线自检：假设备 + 真 MCP 协议，11 项断言（不需要手机）
"C:\Users\oo\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe" C:\Users\oo\.dsh\mcp\iosgg\selftest.js

# 2) 真机连通性：直接问一次 ping
"...node.exe" C:\Users\oo\.dsh\mcp\iosgg\ping_device.js 192.168.3.11 27801
```

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `IOSGG_HOST` | `192.168.3.11` | 设备 IP（与 Makefile 的 `THEOS_DEVICE_IP` 一致） |
| `IOSGG_PORT` | `27801` | 设备侧监听端口 |
| `IOSGG_BRIDGE_KEY` | `igg-mcp-27801` | 桥口令（需与 `MCPBridge.mm` 里的 `kSSMCPToken` 一致） |
| `IOSGG_TIMEOUT_MS` | `10000` | 单次调用超时 |

注意：DSH 会清洗子进程环境里名字含 `KEY|PASSWORD|SECRET|TOKEN` 的变量，所以**不要**指望用 `IOSGG_BRIDGE_KEY` 传口令（会被删掉）；改口令请同时改 tweak 里的常量与服务器默认值。

## 工具一览（22 个）

| 工具 | 用途 |
| --- | --- |
| `iosgg_ping` / `iosgg_status` | 连通性与整体状态（调试器、观察点、断点、最近调用栈） |
| `iosgg_list_modules` / `iosgg_list_symbols` | 模块与符号（按函数名下断点） |
| `iosgg_memory_regions` | VM 区域（判断地址落在栈/堆/模块） |
| `iosgg_read_memory` / `iosgg_write_memory` / `iosgg_disassemble` | 读写内存、反汇编 |
| `iosgg_search_value` / `iosgg_search_refine` / `iosgg_clear_search` | 数值搜索（找变量地址） |
| `iosgg_set_watchpoint` / `iosgg_remove_watchpoint` / `iosgg_list_watchpoints` | 数据观察点（找"谁写了它"） |
| `iosgg_set_function_breakpoint` / `iosgg_remove_function_breakpoint` / `iosgg_list_function_breakpoints` | 执行断点（找"谁调用了它"） |
| `iosgg_recent_hits` / `iosgg_clear_hits` | 命中记录（含调用栈与关键寄存器）——AI 无法被推送，只能主动轮询 |
| `iosgg_call_stack` / `iosgg_continue` | 取调用栈、放行被暂停的线程 |
| `iosgg_log_tail` | tweak 内部最近日志（排障第一步） |

## 推荐工作流（AI 抓"拾取阳光"函数）

1. `iosgg_search_value(type="u32", value="阳光数")` 初筛；
2. 游戏里让阳光变化 → `iosgg_search_refine(mode="changed")` 收敛到唯一地址；
3. `iosgg_set_watchpoint(address, size=4, type="write")`；
4. `iosgg_recent_hits()` 拿到写入指令 PC 与调用栈（frame1 起就是调用链）；
5. `iosgg_disassemble` 回溯函数入口（找 `stp x29, x30, [sp, #-N]!` 序言）；
6. `iosgg_set_function_breakpoint(address, software=true, stopExecution=false)`；
7. 再点一次阳光 → `iosgg_recent_hits()` 直接看到"谁调用了它"；
8. 需要冻结现场做实验时，改 `stopExecution=true`，看完记得 `iosgg_continue`。

## 排障

| 现象 | 处理 |
| --- | --- |
| `连接设备超时` | 游戏没开/tweak 没加载/端口被占；先 `iosgg_log_tail` 看不到就说明连不上，看设备日志有没有"调试桥已监听" |
| 局域网连不上 | 用 `iproxy 27801 27801`（usbmuxd）转发，再把 `IOSGG_HOST` 改成 `127.0.0.1` |
| `token 不正确` | 服务器默认口令与 tweak 里的 `kSSMCPToken` 不一致 |
| 工具列表里没有 `mcp__iosgg__*` | DSH 没重载 profile：重启 DSH（或按 profile 热重载机制重载） |
| 软断点下不上 | 代码页不可写（缺 `VM_PROT_COPY`），先改用 `software=false` 的硬件断点 |
