// epicaudiogames.com: serves public/ as a static site. No dependencies; Railway runs `npm start`.
//
//   PORT            the port to listen on (Railway sets it)
//   CANONICAL_HOST  if set (epicaudiogames.com), requests for www.<host> are redirected to it
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const PUBLIC = path.join(__dirname, 'public');
const PORT = Number(process.env.PORT) || 3000;
const CANONICAL_HOST = (process.env.CANONICAL_HOST || '').trim().toLowerCase();

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.woff2': 'font/woff2',
};

// Pages are revalidated on every visit; images and other assets are cached for a day.
function cacheControl(ext) {
  return ext === '.html' ? 'no-cache' : 'public, max-age=86400';
}

function send(req, res, status, filePath, extraHeaders) {
  const ext = path.extname(filePath).toLowerCase();
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) return notFound(req, res);
    const headers = Object.assign({
      'Content-Type': TYPES[ext] || 'application/octet-stream',
      'Content-Length': stat.size,
      'Last-Modified': stat.mtime.toUTCString(),
      'Cache-Control': cacheControl(ext),
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'SAMEORIGIN',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
    }, extraHeaders || {});

    const since = req.headers['if-modified-since'];
    if (status === 200 && since && Date.parse(since) >= Math.floor(stat.mtimeMs / 1000) * 1000) {
      res.writeHead(304, { 'Cache-Control': headers['Cache-Control'], 'Last-Modified': headers['Last-Modified'] });
      return res.end();
    }

    res.writeHead(status, headers);
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(filePath).on('error', () => res.destroy()).pipe(res);
  });
}

function notFound(req, res) {
  const page = path.join(PUBLIC, '404.html');
  fs.stat(page, (err) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-cache' });
      return res.end('Not found');
    }
    send(req, res, 404, page, { 'Cache-Control': 'no-cache' });
  });
}

// Maps a request path to a file under public/, or null if it points outside it.
function resolve(urlPath) {
  let decoded;
  try {
    decoded = decodeURIComponent(urlPath.split('?')[0]);
  } catch (_) {
    return null;
  }
  if (decoded.includes('\0')) return null;
  let rel = path.posix.normalize('/' + decoded);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(PUBLIC, rel);
  if (file !== PUBLIC && !file.startsWith(PUBLIC + path.sep)) return null;
  return file;
}

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8', Allow: 'GET, HEAD' });
    return res.end('Method not allowed');
  }

  const host = String(req.headers.host || '').split(':')[0].toLowerCase();
  if (CANONICAL_HOST && host === 'www.' + CANONICAL_HOST) {
    res.writeHead(301, { Location: 'https://' + CANONICAL_HOST + req.url, 'Cache-Control': 'public, max-age=86400' });
    return res.end();
  }

  const file = resolve(req.url || '/');
  if (!file) return notFound(req, res);

  fs.stat(file, (err, stat) => {
    if (!err && stat.isDirectory()) {
      // /covers -> /covers/ so relative links inside resolve
      res.writeHead(301, { Location: req.url.split('?')[0] + '/' });
      return res.end();
    }
    if (err && path.extname(file) === '') {
      // /about -> /about.html, if there is one
      return send(req, res, 200, file + '.html');
    }
    send(req, res, 200, file);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`epicaudiogames.com listening on http://0.0.0.0:${PORT}` +
    (CANONICAL_HOST ? ` (www.${CANONICAL_HOST} redirects to ${CANONICAL_HOST})` : ''));
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
