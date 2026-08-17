// DSH 远程 HTTPS 反向代理
// 作用：手机/平板经蒲公英组网用 HTTPS 访问本机 DSH Web，
//       解决非安全上下文（明文 HTTP）下 crypto.randomUUID 不可用导致应用不可用的问题。
// 监听 127.0.0.1:8443，转发到 127.0.0.1:3080，保留 Host 头，支持 WebSocket 升级与 SSE 流。
// 外部入口：netsh interface portproxy 把 蒲公英IP:443 转发到 127.0.0.1:8443。
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const CERT_DIR = path.join(__dirname, 'cert');
const SHARE_DIR = path.join(__dirname, 'share'); // 手机可下载的分享目录
const BACKEND_HOST = '127.0.0.1';
const BACKEND_PORT = 3080;
const LISTEN_HOST = '127.0.0.1';
const LISTEN_PORT = 8443;

function log(msg) {
  console.log(`[remote-proxy ${new Date().toISOString()}] ${msg}`);
}

let tlsOptions;
try {
  const passphrase = fs.readFileSync(path.join(CERT_DIR, 'passphrase.txt'), 'utf8').trim();
  tlsOptions = { pfx: fs.readFileSync(path.join(CERT_DIR, 'server.pfx')), passphrase };
} catch (err) {
  log(`证书加载失败: ${err.message}`);
  process.exit(1);
}

// 分享目录：列出文件并允许下载（仅本组网可访问）
function handleShare(req, res) {
  const url = new URL(req.url, 'http://localhost');
  const rel = decodeURIComponent(url.pathname.slice('/share/'.length));
  if (rel === '' || rel.endsWith('/')) {
    fs.readdir(SHARE_DIR, (err, files) => {
      if (err) { res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' }); res.end('读取分享目录失败'); return; }
      const items = files
        .filter((f) => { try { return fs.statSync(path.join(SHARE_DIR, f)).isFile(); } catch { return false; } })
        .map((f) => `<li><a href="/share/${encodeURIComponent(f)}">${f}</a></li>`)
        .join('');
      const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DSH 文件分享</title></head><body><h2>DSH 文件分享</h2><p>点文件名下载到本机。</p><ul>${items || '<li>（目录为空）</li>'}</ul></body></html>`;
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(html);
    });
    return;
  }
  const target = path.join(SHARE_DIR, path.basename(rel)); // 只允许分享目录内的文件
  fs.stat(target, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' }); res.end('文件不存在'); return; }
    res.writeHead(200, {
      'content-type': 'application/octet-stream',
      'content-length': st.size,
      'content-disposition': `attachment; filename="${encodeURIComponent(path.basename(target))}"`,
    });
    fs.createReadStream(target).pipe(res);
  });
}

// 普通 HTTP(S) 请求转发（含 SSE 流式响应）
function handleRequest(req, res) {
  if (req.url.startsWith('/share/') || req.url === '/share') {
    handleShare(req, res);
    return;
  }
  // 客户端中途断开（手机浏览器常见行为）时，主动销毁后端请求，避免泄漏与进程崩溃
  req.on('aborted', () => proxyReq.destroy());
  res.on('error', () => {
    /* 客户端断开导致的写入错误，忽略即可 */
  });
  const proxyReq = http.request({
    host: BACKEND_HOST,
    port: BACKEND_PORT,
    method: req.method,
    path: req.url,
    headers: req.headers, // 保留原 Host 头，DSH 信任围栏按 Host 校验
  }, (proxyRes) => {
    proxyRes.on('error', () => res.destroy());
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });
  proxyReq.on('error', (err) => {
    log(`后端请求失败: ${err.message}`);
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('proxy backend error');
  });
  req.pipe(proxyReq);
}

// WebSocket 升级转发（DSH 的下行事件流走 WS）
function handleUpgrade(req, socket, head) {
  const proxyReq = http.request({
    host: BACKEND_HOST,
    port: BACKEND_PORT,
    method: req.method,
    path: req.url,
    headers: req.headers,
  });
  proxyReq.on('upgrade', (proxyRes, proxySocket, proxyHead) => {
    const proto = proxyRes.httpVersion.startsWith('1.1') ? 'HTTP/1.1' : 'HTTP/1.0';
    let raw = `${proto} ${proxyRes.statusCode} ${proxyRes.statusMessage}\r\n`;
    for (let i = 0; i < proxyRes.rawHeaders.length; i += 2) {
      raw += `${proxyRes.rawHeaders[i]}: ${proxyRes.rawHeaders[i + 1]}\r\n`;
    }
    raw += '\r\n';
    socket.write(raw);
    if (proxyHead && proxyHead.length) socket.write(proxyHead);
    proxySocket.pipe(socket);
    socket.pipe(proxySocket);
  });
  proxyReq.on('error', (err) => {
    log(`WebSocket 升级失败: ${err.message}`);
    socket.destroy();
  });
  proxyReq.end();
}

const server = https.createServer(tlsOptions, handleRequest);
server.on('upgrade', handleUpgrade);
server.on('error', (err) => {
  log(`服务错误: ${err.message}`);
  process.exit(1);
});
server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  log(`HTTPS 代理已启动 ${LISTEN_HOST}:${LISTEN_PORT} -> http://${BACKEND_HOST}:${BACKEND_PORT}`);
});
