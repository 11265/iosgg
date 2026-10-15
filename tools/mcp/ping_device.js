#!/usr/bin/env node
/*
 * ping_device.js —— 直接连手机里的调试桥做一次 ping，用来确认 tweak 是否在监听
 *
 * 用法：
 *   node ping_device.js                 # 用默认 192.168.3.11:27801
 *   node ping_device.js 127.0.0.1 27801 # 走了 iproxy 转发时
 * 或设置环境变量 IOSGG_HOST / IOSGG_PORT / IOSGG_BRIDGE_KEY
 */

'use strict';

const net = require('net');

const HOST = process.env.IOSGG_HOST || process.argv[2] || '192.168.3.11';
const PORT = Number(process.env.IOSGG_PORT || process.argv[3] || 27801);
const KEY = process.env.IOSGG_BRIDGE_KEY || 'igg-mcp-27801';

console.log(`连接 ${HOST}:${PORT} ...`);

const socket = net.connect({ host: HOST, port: PORT });
let buffer = '';

const timer = setTimeout(() => {
  console.error(`失败：${HOST}:${PORT} 5 秒内无响应。`);
  console.error('请确认：游戏在运行、tweak 已加载（日志里有 "[MCP] 调试桥已监听"）、端口未被占用。');
  process.exit(2);
}, 5000);

socket.on('connect', () => {
  socket.write(JSON.stringify({ id: 1, token: KEY, cmd: 'ping', args: {} }) + '\n');
});

socket.on('data', (chunk) => {
  buffer += chunk.toString('utf8');
  const index = buffer.indexOf('\n');
  if (index >= 0) {
    console.log('设备响应:', buffer.slice(0, index));
    clearTimeout(timer);
    socket.end();
    process.exit(0);
  }
});

socket.on('error', (error) => {
  clearTimeout(timer);
  console.error('连接失败:', error.message);
  process.exit(3);
});
