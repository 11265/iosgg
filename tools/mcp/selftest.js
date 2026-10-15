#!/usr/bin/env node
/*
 * selftest.js —— 对 iosgg_mcp_server.js 做端到端自检（不需要真机）
 *
 * 做法：起一个"假设备"TCP 服务（实现和 tweak 里 SSMCPBridge 一样的行协议），
 * 用它作为 MCP 服务器的后端，然后用 JSON-RPC 驱动 MCP 服务器的 stdio，
 * 断言 initialize / tools/list / tools/call 的行为与口令校验。
 *
 * 运行： node selftest.js
 */

'use strict';

const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

const BRIDGE_KEY = 'test-key-123';

let failures = 0;
function check(name, ok, detail) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok || !detail ? '' : '  -> ' + detail}`);
  if (!ok) failures++;
}

// ---------------------------------------------------------------------------
// 1. 假设备：实现 tweak 侧的行协议
// ---------------------------------------------------------------------------

function startMockDevice() {
  return new Promise((resolve) => {
    const server = net.createServer((socket) => {
      let buffer = '';
      socket.on('data', (chunk) => {
        buffer += chunk.toString('utf8');
        let index;
        while ((index = buffer.indexOf('\n')) >= 0) {
          const line = buffer.slice(0, index);
          buffer = buffer.slice(index + 1);
          if (!line.trim()) continue;

          let request;
          try {
            request = JSON.parse(line);
          } catch (error) {
            continue;
          }

          if (request.token !== BRIDGE_KEY) {
            socket.write(JSON.stringify({ id: request.id, ok: false, error: 'token 不正确' }) + '\n');
            continue;
          }

          const reply = (result) =>
            socket.write(JSON.stringify({ id: request.id, ok: true, result }) + '\n');
          const fail = (message) =>
            socket.write(JSON.stringify({ id: request.id, ok: false, error: message }) + '\n');

          const args = request.args || {};
          switch (request.cmd) {
            case 'ping':
              reply({ pong: true, pid: 4242, port: server.address().port });
              break;
            case 'status':
              reply({
                pid: 4242,
                processName: 'pvz',
                debugging: true,
                watchpoints: [{ address: '0x1000', type: 1 }],
                functionBreakpoints: [],
                breakpointStopsExecution: false,
                lastCallStack: ['0x100', '0x200'],
              });
              break;
            case 'read_memory':
              reply({ address: args.address, size: 4, hex: 'deadbeef' });
              break;
            case 'recent_hits':
              reply({
                hits: [
                  {
                    kind: 'watchpoint',
                    address: '0x1000',
                    pc: '0x400100',
                    callStack: ['0x400100', '0x400200'],
                  },
                ],
                total: 1,
              });
              break;
            case 'log_tail':
              reply({ logs: ['[MCP] 调试桥已监听 0.0.0.0:27801', '[断点] 命中 0x400100'] });
              break;
            default:
              fail(`未知命令: ${request.cmd}`);
          }
        }
      });
    });

    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

// ---------------------------------------------------------------------------
// 2. 驱动 MCP 服务器
// ---------------------------------------------------------------------------

function startMcpServer(port) {
  const child = spawn(process.execPath, [path.join(__dirname, 'iosgg_mcp_server.js')], {
    env: Object.assign({}, process.env, {
      IOSGG_HOST: '127.0.0.1',
      IOSGG_PORT: String(port),
      IOSGG_BRIDGE_KEY: BRIDGE_KEY,
      IOSGG_TIMEOUT_MS: '5000',
    }),
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  const pending = new Map();
  let buffer = '';

  child.stdout.on('data', (chunk) => {
    buffer += chunk.toString('utf8');
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      if (!line.trim()) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch (error) {
        console.log('MCP 服务器输出了非 JSON:', line.slice(0, 200));
        continue;
      }
      const entry = pending.get(message.id);
      if (entry) {
        pending.delete(message.id);
        entry(message);
      }
    }
  });

  child.stderr.on('data', (chunk) => {
    // 服务器日志走 stderr，测试时静默（想看就取消注释）
    // process.stderr.write('[server] ' + chunk.toString());
    void chunk;
  });

  let nextId = 1;
  const rpc = (method, params) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      const timer = setTimeout(() => reject(new Error(`RPC 超时: ${method}`)), 6000);
      pending.set(id, (message) => {
        clearTimeout(timer);
        resolve(message);
      });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    });

  const notify = (method, params) =>
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');

  return { child, rpc, notify };
}

// ---------------------------------------------------------------------------
// 3. 断言
// ---------------------------------------------------------------------------

async function main() {
  const mock = await startMockDevice();
  const port = mock.address().port;
  const { child, rpc, notify } = startMcpServer(port);

  try {
    const init = await rpc('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'selftest', version: '0' },
    });
    check('initialize 返回 serverInfo', init.result && init.result.serverInfo &&
      init.result.serverInfo.name === 'iosgg-debug-bridge', JSON.stringify(init).slice(0, 200));
    check('initialize 回显协议版本', init.result && init.result.protocolVersion === '2025-06-18',
      String(init.result && init.result.protocolVersion));
    notify('notifications/initialized', {});

    const list = await rpc('tools/list', {});
    const tools = (list.result && list.result.tools) || [];
    check('tools/list 返回 >= 20 个工具', tools.length >= 20, `实际 ${tools.length}`);
    check('工具名都带 iosgg_ 前缀', tools.every((tool) => tool.name.startsWith('iosgg_')),
      tools.map((tool) => tool.name).join(','));
    check('每个工具都有 inputSchema', tools.every((tool) => tool.inputSchema && tool.inputSchema.type === 'object'));

    const ping = await rpc('tools/call', { name: 'iosgg_ping', arguments: {} });
    const pingText = ping.result && ping.result.content && ping.result.content[0] && ping.result.content[0].text;
    check('调用 iosgg_ping 成功（说明口令校验通过）',
      ping.result && ping.result.isError === false && /"pong": true/.test(pingText || ''), pingText);

    const read = await rpc('tools/call', {
      name: 'iosgg_read_memory',
      arguments: { address: '0x1000', size: 4 },
    });
    const readText = read.result.content[0].text;
    check('调用 iosgg_read_memory 返回内存内容', /deadbeef/.test(readText), readText);

    const hits = await rpc('tools/call', { name: 'iosgg_recent_hits', arguments: { limit: 5 } });
    check('调用 iosgg_recent_hits 返回命中与调用栈',
      /"callStack"/.test(hits.result.content[0].text), hits.result.content[0].text);

    // MCP 规范：未知工具属于协议级错误（JSON-RPC error）；
    // 工具"执行失败"才用 result.isError（下面 badCmd 那条覆盖）。
    const unknown = await rpc('tools/call', { name: 'iosgg_not_exist', arguments: {} });
    check('未知工具返回 JSON-RPC 错误(-32602)',
      !!(unknown.error && unknown.error.code === -32602), JSON.stringify(unknown).slice(0, 160));

    const badCmd = await rpc('tools/call', { name: 'iosgg_list_symbols', arguments: {} });
    check('设备侧报错会透传为 isError', badCmd.result && badCmd.result.isError === true &&
      /未知命令/.test(badCmd.result.content[0].text), badCmd.result.content[0].text);

    const ping2 = await rpc('ping', {});
    check('MCP ping 有响应', ping2.result !== undefined, JSON.stringify(ping2));
  } catch (error) {
    check('自检未抛异常', false, error && error.message);
  } finally {
    child.kill();
    mock.close();
  }

  console.log(failures === 0 ? '\n全部通过' : `\n存在失败（${failures} 项）`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
