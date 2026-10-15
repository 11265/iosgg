#!/usr/bin/env node
/*
 * iosgg_mcp_server.js —— iOS 调试 tweak 的 MCP(stdio) 服务器
 *
 * 架构：
 *   DSH / 任意 MCP 客户端  --stdio(JSON-RPC)-->  本进程  --TCP(一行一个 JSON)-->  手机里的 SSMCPBridge
 *
 * 依赖：只用 Node 内置模块（net / readline），不需要 npm install。
 *
 * 环境变量：
 *   IOSGG_HOST        设备 IP（默认 192.168.3.11，和 Makefile 里的 THEOS_DEVICE_IP 一致）
 *   IOSGG_PORT        设备侧监听端口（默认 27801）
 *   IOSGG_BRIDGE_KEY  设备侧口令（默认 igg-mcp-27801）
 *   IOSGG_TIMEOUT_MS  单次调用超时（默认 10000）
 *
 * 注意：stdout 是协议通道，只能输出 JSON-RPC；所有日志走 stderr。
 */

'use strict';

const net = require('net');
const readline = require('readline');

const HOST = process.env.IOSGG_HOST || '192.168.3.11';
const PORT = Number(process.env.IOSGG_PORT || 27801);
const BRIDGE_KEY = process.env.IOSGG_BRIDGE_KEY || 'igg-mcp-27801';
const CALL_TIMEOUT_MS = Number(process.env.IOSGG_TIMEOUT_MS || 10000);
const CONNECT_TIMEOUT_MS = Number(process.env.IOSGG_CONNECT_TIMEOUT_MS || 5000);

const PROTOCOL_VERSION_FALLBACK = '2024-11-05';

function log(...args) {
  process.stderr.write('[iosgg-mcp] ' + args.join(' ') + '\n');
}

// ---------------------------------------------------------------------------
// 与设备侧 SSMCPBridge 的 TCP 通道
// ---------------------------------------------------------------------------

let socket = null;
let recvBuffer = '';
let nextRequestId = 1;
const pending = new Map();

function rejectAllPending(reason) {
  for (const [id, entry] of pending) {
    clearTimeout(entry.timer);
    entry.reject(new Error(reason));
  }
  pending.clear();
}

function connect() {
  return new Promise((resolve, reject) => {
    if (socket && !socket.destroyed) {
      resolve();
      return;
    }

    const sock = net.connect({ host: HOST, port: PORT });
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      sock.destroy();
      reject(new Error(
        `连接设备超时 ${HOST}:${PORT}。请确认：游戏正在运行且 tweak 已加载（日志里应有 "[MCP] 调试桥已监听"）、` +
        `手机与电脑同一网段；若局域网被限制，可用 iproxy 把设备端口转发到本机后用 IOSGG_HOST=127.0.0.1。`));
    }, CONNECT_TIMEOUT_MS);

    sock.once('connect', () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket = sock;
      recvBuffer = '';
      log(`已连接设备 ${HOST}:${PORT}`);
      resolve();
    });

    sock.on('data', (chunk) => {
      recvBuffer += chunk.toString('utf8');
      let index;
      while ((index = recvBuffer.indexOf('\n')) >= 0) {
        const line = recvBuffer.slice(0, index);
        recvBuffer = recvBuffer.slice(index + 1);
        if (!line.trim()) continue;
        let message;
        try {
          message = JSON.parse(line);
        } catch (error) {
          log('设备返回了非 JSON 行:', line.slice(0, 200));
          continue;
        }
        const entry = pending.get(message.id);
        if (!entry) continue;
        pending.delete(message.id);
        clearTimeout(entry.timer);
        if (message.ok) {
          entry.resolve(message.result || {});
        } else {
          entry.reject(new Error(message.error || '设备返回失败'));
        }
      }
    });

    sock.on('error', (error) => {
      log('socket 错误:', error.message);
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(error);
      }
      rejectAllPending('设备连接错误: ' + error.message);
      socket = null;
    });

    sock.on('close', () => {
      rejectAllPending('设备连接已关闭');
      socket = null;
    });
  });
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** 调用设备侧命令；返回 result 对象 */
async function callBridge(cmd, args, { retry = true } = {}) {
  await connect();

  const attempt = () => new Promise((resolve, reject) => {
    const id = nextRequestId++;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`调用超时(${CALL_TIMEOUT_MS}ms): ${cmd}`));
    }, CALL_TIMEOUT_MS);

    pending.set(id, { resolve, reject, timer });
    try {
      socket.write(JSON.stringify({ id, token: BRIDGE_KEY, cmd, args: args || {} }) + '\n');
    } catch (error) {
      clearTimeout(timer);
      pending.delete(id);
      reject(error);
    }
  });

  try {
    return await attempt();
  } catch (error) {
    // 连接被重启（例如 tweak 重启、切前台）时重试一次
    if (retry && /closed|EPIPE|ECONNRESET|not connected/i.test(error.message)) {
      socket = null;
      await sleep(300);
      await connect();
      return attempt();
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// MCP 工具定义
// ---------------------------------------------------------------------------

const A = (description) => ({ type: 'string', description });

const TOOLS = [
  {
    name: 'iosgg_ping',
    description: '检查与手机里 tweak 的调试桥是否连通，返回 pid 和端口。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'ping',
  },
  {
    name: 'iosgg_status',
    description: '调试器整体状态：是否已启动、当前观察点/执行断点、最近一次调用栈。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'status',
  },
  {
    name: 'iosgg_list_modules',
    description: '列出进程内已加载的所有模块（名称/基址/结束地址/路径），用来做地址→模块+偏移的换算。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'list_modules',
  },
  {
    name: 'iosgg_list_symbols',
    description: '列出某个模块的符号（可按名字过滤），用于"按函数名下断点"。module 传模块名（如 pvz），或直接给 moduleBase。',
    inputSchema: {
      type: 'object',
      properties: {
        module: A('模块名（可只写文件名，如 "pvz" 或 "libil2cpp.so"）'),
        moduleBase: A('模块基址，如 "0x104a00000"（与 module 二选一）'),
        filter: A('符号名包含的子串，如 "Sun"'),
        max: { type: 'number', description: '最多返回多少个符号（默认 200，上限 2000）' },
      },
      additionalProperties: false,
    },
    cmd: 'list_symbols',
  },
  {
    name: 'iosgg_memory_regions',
    description: '列出进程 VM 区域（起止/大小/权限/所属文件），用于判断某个地址落在栈、堆还是某个模块。',
    inputSchema: {
      type: 'object',
      properties: { max: { type: 'number', description: '最多返回多少条（默认 200）' } },
      additionalProperties: false,
    },
    cmd: 'memory_regions',
  },
  {
    name: 'iosgg_read_memory',
    description: '读取内存，返回十六进制字符串。size 上限 256KB。',
    inputSchema: {
      type: 'object',
      properties: {
        address: A('地址，如 "0x104a3c1f0"'),
        size: { type: 'number', description: '字节数（默认 64）' },
      },
      required: ['address'],
      additionalProperties: false,
    },
    cmd: 'read_memory',
  },
  {
    name: 'iosgg_write_memory',
    description: '写入内存（十六进制串，长度需为偶数）。可用于改数值或打补丁。',
    inputSchema: {
      type: 'object',
      properties: {
        address: A('地址'),
        hex: A('十六进制字节串，如 "01000000" 或 "01 00 00 00"'),
      },
      required: ['address', 'hex'],
      additionalProperties: false,
    },
    cmd: 'write_memory',
  },
  {
    name: 'iosgg_disassemble',
    description: '反汇编从 address 开始的若干条指令（ARM64），返回地址/机器码/文本/是否 BL 及跳转目标。',
    inputSchema: {
      type: 'object',
      properties: {
        address: A('起始地址'),
        count: { type: 'number', description: '指令条数（默认 10，上限 200）' },
      },
      required: ['address'],
      additionalProperties: false,
    },
    cmd: 'disassemble',
  },
  {
    name: 'iosgg_set_watchpoint',
    description: '在数据地址上设置硬件观察点（读/写/读写）。命中不会暂停进程，命中记录用 iosgg_recent_hits 取。' +
      '这是"从数据反推函数"的第一步：给阳光数量下写观察点，就能拿到写入它的指令 PC。',
    inputSchema: {
      type: 'object',
      properties: {
        address: A('被监视的数据地址'),
        size: { type: 'number', description: '监视宽度，1/2/4/8（建议 4）' },
        type: A('"write"（默认）| "read" | "readwrite"'),
      },
      required: ['address'],
      additionalProperties: false,
    },
    cmd: 'set_watchpoint',
  },
  {
    name: 'iosgg_remove_watchpoint',
    description: '移除数据观察点。',
    inputSchema: {
      type: 'object',
      properties: { address: A('观察点地址') },
      required: ['address'],
      additionalProperties: false,
    },
    cmd: 'remove_watchpoint',
  },
  {
    name: 'iosgg_list_watchpoints',
    description: '列出当前所有观察点。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'list_watchpoints',
  },
  {
    name: 'iosgg_set_function_breakpoint',
    description: '在函数入口下"执行断点"，用来抓"这个函数被谁调用"。software=true 走 BRK 补丁（推荐，全局生效、数量几乎无限）；' +
      'stopExecution=true 时命中会暂停线程并弹窗（AI 需要随后调用 iosgg_continue 放行），默认 false 只记录命中，不卡游戏。',
    inputSchema: {
      type: 'object',
      properties: {
        address: A('函数入口地址'),
        software: { type: 'boolean', description: '是否用软件断点（默认 true）' },
        stopExecution: { type: 'boolean', description: '命中是否暂停线程（默认 false，适合 AI 无人值守）' },
        hitCount: { type: 'number', description: '忽略前 N-1 次命中（默认 0 = 第一次就记录）' },
      },
      required: ['address'],
      additionalProperties: false,
    },
    cmd: 'set_function_breakpoint',
  },
  {
    name: 'iosgg_remove_function_breakpoint',
    description: '移除执行断点。',
    inputSchema: {
      type: 'object',
      properties: { address: A('断点地址') },
      required: ['address'],
      additionalProperties: false,
    },
    cmd: 'remove_function_breakpoint',
  },
  {
    name: 'iosgg_list_function_breakpoints',
    description: '列出执行断点及其命中次数。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'list_function_breakpoints',
  },
  {
    name: 'iosgg_continue',
    description: '继续执行被断点停住的线程（stopExecution=true 导致暂停后必须调用，否则游戏卡住）。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'continue_thread',
  },
  {
    name: 'iosgg_call_stack',
    description: '取调用栈（十六进制地址数组）。不传 threadId 时返回最近一次命中的调用栈；frame0 是触发指令，frame1 起是各级调用者。',
    inputSchema: {
      type: 'object',
      properties: { threadId: A('线程端口（来自 recent_hits 的 threadId），可选') },
      additionalProperties: false,
    },
    cmd: 'call_stack',
  },
  {
    name: 'iosgg_recent_hits',
    description: '拉取最近的观察点/执行断点命中记录（含地址、PC、线程、命中次数、调用栈、关键寄存器）。' +
      'AI 无法被推送，需要主动轮询这个工具。',
    inputSchema: {
      type: 'object',
      properties: { limit: { type: 'number', description: '最多返回多少条（默认 20，最多 200）' } },
      additionalProperties: false,
    },
    cmd: 'recent_hits',
  },
  {
    name: 'iosgg_clear_hits',
    description: '清空命中记录（开始一轮新的观察前先清一下更干净）。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'clear_hits',
  },
  {
    name: 'iosgg_search_value',
    description: '在可写数据区里精确搜索数值，返回命中的地址列表（这是找"阳光数量"这类变量的入口）。' +
      'type 支持 u8/u16/u32/u64/f32/f64；value 十进制或 0x 十六进制。',
    inputSchema: {
      type: 'object',
      properties: {
        type: A('u8 | u16 | u32（默认） | u64 | f32 | f64'),
        value: A('要搜索的值，如 "150" 或 "0x64"'),
        max: { type: 'number', description: '最多返回多少条（默认 2000，上限 20000）' },
      },
      required: ['value'],
      additionalProperties: false,
    },
    cmd: 'search_value',
  },
  {
    name: 'iosgg_search_refine',
    description: '在上一次搜索结果里继续筛选：mode="eq"（等于新值，默认）、"changed"（值变了）、"unchanged"（值没变）。' +
      '典型流程：search_value 初筛 → 让游戏里数值变化 → search_refine(mode="changed") 收敛到唯一地址。',
    inputSchema: {
      type: 'object',
      properties: {
        type: A('必须和上一次 search_value 相同'),
        value: A('mode="eq" 时必填'),
        mode: A('"eq"（默认）| "changed" | "unchanged"'),
        max: { type: 'number', description: '最多返回多少条' },
      },
      required: ['type'],
      additionalProperties: false,
    },
    cmd: 'search_refine',
  },
  {
    name: 'iosgg_clear_search',
    description: '清空搜索会话。',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    cmd: 'clear_search',
  },
  {
    name: 'iosgg_log_tail',
    description: '读取 tweak 内部最近的日志（调试器启动、断点命中、调用栈、错误等），排障时先看这个。',
    inputSchema: {
      type: 'object',
      properties: { limit: { type: 'number', description: '最多返回多少条（默认 50）' } },
      additionalProperties: false,
    },
    cmd: 'log_tail',
  },
];

const TOOLS_BY_NAME = new Map(TOOLS.map((tool) => [tool.name, tool]));

// ---------------------------------------------------------------------------
// MCP stdio 协议
// ---------------------------------------------------------------------------

function send(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

function sendResult(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function sendError(id, code, message) {
  send({ jsonrpc: '2.0', id, error: { code, message } });
}

async function handleToolsCall(id, params) {
  const name = params && params.name;
  const tool = TOOLS_BY_NAME.get(name);
  if (!tool) {
    sendError(id, -32602, `未知工具: ${name}`);
    return;
  }

  try {
    const result = await callBridge(tool.cmd, params.arguments || {});
    sendResult(id, {
      content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
      isError: false,
    });
  } catch (error) {
    sendResult(id, {
      content: [{ type: 'text', text: `调用失败: ${error.message}` }],
      isError: true,
    });
  }
}

function handleMessage(message) {
  const { id, method, params } = message;

  // 通知（没有 id）不需要回复
  if (id === undefined || id === null) {
    return;
  }

  switch (method) {
    case 'initialize':
      sendResult(id, {
        protocolVersion: (params && params.protocolVersion) || PROTOCOL_VERSION_FALLBACK,
        capabilities: { tools: {} },
        serverInfo: { name: 'iosgg-debug-bridge', version: '1.0.0' },
        instructions:
          '这是 iPhone 上 iOS 调试 tweak 的桥。典型工作流：' +
          '1) iosgg_ping / iosgg_status 确认连通；' +
          '2) iosgg_search_value 找变量地址，数值变化后用 iosgg_search_refine 收敛；' +
          '3) iosgg_set_watchpoint 下写观察点，iosgg_recent_hits 拿到写入指令 PC 与调用栈；' +
          '4) 用 iosgg_disassemble / iosgg_list_symbols 找到函数入口，再 iosgg_set_function_breakpoint 抓"谁调用了它"；' +
          '5) 若开了 stopExecution，记得 iosgg_continue 放行，否则游戏会一直停住。',
      });
      return;

    case 'ping':
      sendResult(id, {});
      return;

    case 'tools/list':
      sendResult(id, {
        tools: TOOLS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })),
      });
      return;

    case 'tools/call':
      handleToolsCall(id, params || {});
      return;

    case 'resources/list':
      sendResult(id, { resources: [] });
      return;

    case 'prompts/list':
      sendResult(id, { prompts: [] });
      return;

    default:
      sendError(id, -32601, `未实现的方法: ${method}`);
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });

rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let message;
  try {
    message = JSON.parse(trimmed);
  } catch (error) {
    log('收到非 JSON 输入，忽略:', trimmed.slice(0, 200));
    return;
  }
  try {
    handleMessage(message);
  } catch (error) {
    log('处理消息异常:', error && error.stack ? error.stack : String(error));
  }
});

rl.on('close', () => {
  log('stdin 关闭，退出');
  if (socket) {
    socket.destroy();
  }
  process.exit(0);
});

log(`启动：目标设备 ${HOST}:${PORT}（node ${process.version}）`);
