// epicaudiogames.com: serves public/ as a static site, and the packs' zips the apps download from /packs/. No
// dependencies; Railway runs `npm start`.
//
//   PORT            the port to listen on (Railway sets it)
//   CANONICAL_HOST  if set (epicaudiogames.com), requests for www.<host> are redirected to it
//   PACKS_DIR       the folder of <pack>-<version>.zip files served at /packs/ (default: web/packs; on Railway, a
//                   volume: see the README)
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { pipeline } = require('stream');

const PUBLIC = path.join(__dirname, 'public');
const PORT = Number(process.env.PORT) || 3000;
const CANONICAL_HOST = (process.env.CANONICAL_HOST || '').trim().toLowerCase();
const PACKS_DIR = path.resolve(process.env.PACKS_DIR || path.join(__dirname, 'packs'));

// A pack's zip as tools/make_pack.py names it ("the-werewolf-stories-1.zip"). Nothing else under /packs/ is served,
// so there's no listing and no way out of the folder.
const PACK_ZIP = /^\/packs\/([a-z0-9]+(?:-[a-z0-9]+)*-[0-9]+\.zip)$/;

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

// The one range a Range header asks for ("bytes=0-99", "bytes=100-", "bytes=-100") as [first, last] byte; null to
// send the whole file (no header, several ranges, or one that can't be read), false if it starts past the end.
function byteRange(header, size) {
  const m = /^bytes=(\d*)-(\d*)$/.exec(String(header || '').trim());
  if (!m || (m[1] === '' && m[2] === '')) return null;
  if (m[1] === '') {
    // the last n bytes
    const n = Number(m[2]);
    return n > 0 && size > 0 ? [Math.max(size - n, 0), size - 1] : false;
  }
  const first = Number(m[1]);
  const last = m[2] === '' ? size - 1 : Number(m[2]);
  if (m[2] !== '' && last < first) return null;
  return first < size ? [first, Math.min(last, size - 1)] : false;
}

// A pack's zip. The apps check its size and SHA-256 against games/catalog.json, and a name never gets other bytes (a
// changed pack gets a new version), so it's cached for a year. Ranges let a download that broke off carry on.
function sendPack(req, res, name) {
  const file = path.join(PACKS_DIR, name);
  fs.stat(file, (err, stat) => {
    if (err || !stat.isFile()) return notFound(req, res);
    const etag = `"${Math.floor(stat.mtimeMs).toString(16)}-${stat.size.toString(16)}"`;
    const lastModified = stat.mtime.toUTCString();
    const headers = {
      'Content-Type': 'application/zip',
      'Accept-Ranges': 'bytes',
      ETag: etag,
      'Last-Modified': lastModified,
      'Cache-Control': 'public, max-age=31536000, immutable',
      'X-Content-Type-Options': 'nosniff',
    };

    // The client has it already.
    const match = req.headers['if-none-match'];
    const since = req.headers['if-modified-since'];
    const fresh = match
      ? match.split(',').some((t) => t.trim().replace(/^W\//, '') === etag || t.trim() === '*')
      : Boolean(since) && Date.parse(since) >= Math.floor(stat.mtimeMs / 1000) * 1000;
    if (fresh) {
      res.writeHead(304, { ETag: etag, 'Last-Modified': lastModified, 'Cache-Control': headers['Cache-Control'] });
      return res.end();
    }

    // A range, unless If-Range names another version of the file (then all of it, as it is now).
    const ifRange = req.headers['if-range'];
    const current = !ifRange || ifRange === etag || ifRange === lastModified;
    const range = req.method === 'GET' && current ? byteRange(req.headers.range, stat.size) : null;
    if (range === false) {
      res.writeHead(416, { 'Content-Range': `bytes */${stat.size}`, 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('Range not satisfiable');
    }
    const [first, last] = range || [0, stat.size - 1];
    if (range) headers['Content-Range'] = `bytes ${first}-${last}/${stat.size}`;
    headers['Content-Length'] = stat.size === 0 ? 0 : last - first + 1;
    res.writeHead(range ? 206 : 200, headers);
    if (req.method === 'HEAD' || stat.size === 0) return res.end();
    // pipeline closes the file when the client goes away mid-download
    pipeline(fs.createReadStream(file, { start: first, end: last }), res, () => {});
  });
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

  const urlPath = (req.url || '/').split('?')[0];
  if (urlPath === '/packs' || urlPath.startsWith('/packs/')) {
    const pack = PACK_ZIP.exec(urlPath);
    return pack ? sendPack(req, res, pack[1]) : notFound(req, res);
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
  let zips;
  try {
    zips = fs.readdirSync(PACKS_DIR).filter((n) => PACK_ZIP.test('/packs/' + n));
  } catch (_) {
    zips = null;
  }
  console.log(`packs from ${PACKS_DIR}: ` + (zips ? zips.join(', ') || 'none yet' : 'no such folder'));
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
