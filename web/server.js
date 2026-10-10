// epicaudiogames.com: serves public/ as a static site, and takes the apps' usage data at /api. Railway runs
// `npm start`.
//
//   PORT            the port to listen on (Railway sets it)
//   CANONICAL_HOST  if set (epicaudiogames.com), requests for www.<host> are redirected to it
//   DATABASE_URL    the Postgres database usage data goes to (on Railway, a reference to the Postgres service's own).
//                   Without it, or while the database can't be reached, the site works as ever and /api answers 503,
//                   so the apps keep their events and send them later.
//
// The API (the apps send to https://epicaudiogames.com/api/...; JSON in and out, never cached):
//   POST /api/events  a JSON array of 1 to 100 events (analytics/whitelist.js has their shape; analytics/events.json
//                     is the whitelist), at most 64 KB, Content-Type: application/json, not compressed.
//                     202 stored · 400 refused, nothing of it stored ({"error": why}) · 413 too big · 415 not JSON
//                     · 429 too many requests (Retry-After) · 503 no database: send it again later
//   POST /api/forget  {"install_id": "<uuid>"}: deletes that install's usage data. 202 (also when there was none),
//                     or 400, 413, 415, 429, 503 as above.
//   Anything but POST on /api gets 405. Nothing about a request (its body, the IP address it came from) is logged or
//   kept: the IP address is only a key for the rate limit, in memory.
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { checkBatch, checkForget } = require('./analytics/whitelist');
const { openStore, describe } = require('./analytics/store');

const PUBLIC = path.join(__dirname, 'public');
const PORT = Number(process.env.PORT) || 3000;
const CANONICAL_HOST = (process.env.CANONICAL_HOST || '').trim().toLowerCase();

const MAX_BODY = 64 * 1024;
const DAY = 24 * 60 * 60 * 1000;

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

// A token bucket per client: up to `burst` requests at once, refilled at `perMinute` a minute. It lives in memory
// only, keyed by the IP address, which isn't written anywhere; a bucket that has filled up again is forgotten.
class RateLimiter {
  constructor({ perMinute = 60, burst = 20, now = Date.now, maxClients = 100000 } = {}) {
    this.rate = perMinute / 60000; // tokens a millisecond
    this.burst = burst;
    this.now = now;
    this.maxClients = maxClients;
    this.buckets = new Map();
    this.swept = now();
  }

  // 0 if the request can go ahead, else how many seconds until it could.
  take(key) {
    const t = this.now();
    if (t - this.swept > 60000 || this.buckets.size >= this.maxClients) this.sweep(t);
    let bucket = this.buckets.get(key);
    if (!bucket) {
      bucket = { tokens: this.burst, at: t };
      this.buckets.set(key, bucket);
    }
    bucket.tokens = Math.min(this.burst, bucket.tokens + (t - bucket.at) * this.rate);
    bucket.at = t;
    if (bucket.tokens < 1) return Math.ceil((1 - bucket.tokens) / this.rate / 1000);
    bucket.tokens -= 1;
    return 0;
  }

  sweep(t) {
    for (const [key, bucket] of this.buckets) {
      if (bucket.tokens + (t - bucket.at) * this.rate >= this.burst) this.buckets.delete(key);
    }
    // a flood from more addresses than that: start everyone afresh rather than run out of memory
    if (this.buckets.size >= this.maxClients) this.buckets.clear();
    this.swept = t;
  }
}

// Whose bucket a request comes out of. Cloudflare, in front of the site, names the visitor in CF-Connecting-IP and
// Railway's proxy in X-Real-IP; the socket's own address is the proxy's, the same for everyone.
function clientIp(req) {
  return String(req.headers['cf-connecting-ip'] || req.headers['x-real-ip'] || req.socket.remoteAddress || '');
}

// An answer from the API: JSON, never cached.
function reply(res, status, body, extraHeaders) {
  const text = JSON.stringify(body);
  res.writeHead(status, Object.assign({
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  }, extraHeaders || {}));
  res.end(text);
}

function isJson(contentType) {
  const [type, ...params] = String(contentType || '').toLowerCase().split(';').map((s) => s.trim());
  return type === 'application/json' && params.every((p) => !p.startsWith('charset=') || /^charset="?utf-8"?$/.test(p));
}

// The request's body as text, or a 413 once it's over `max` bytes (straight away when Content-Length says so, before
// reading any of it). What's left of a body that's too big is read and thrown away, so the client gets its answer.
function readBody(req, max, done) {
  if (Number(req.headers['content-length']) > max) return done(413);
  const chunks = [];
  let size = 0;
  const onData = (chunk) => {
    size += chunk.length;
    if (size <= max) return chunks.push(chunk);
    req.removeListener('data', onData);
    req.removeListener('end', onEnd);
    req.resume();
    done(413);
  };
  const onEnd = () => done(null, Buffer.concat(chunks).toString('utf8'));
  req.on('data', onData);
  req.on('end', onEnd);
}

// The usage data: POST /api/events and POST /api/forget.
function api(req, res, urlPath, { store, limiter, log }) {
  if (req.method !== 'POST') return reply(res, 405, { error: 'POST only' }, { Allow: 'POST' });
  if (urlPath !== '/api/events' && urlPath !== '/api/forget') return reply(res, 404, { error: 'no such endpoint' });

  const wait = limiter.take(clientIp(req));
  if (wait) return reply(res, 429, { error: 'too many requests' }, { 'Retry-After': String(wait) });
  if (!isJson(req.headers['content-type'])) {
    return reply(res, 415, { error: 'expected Content-Type: application/json' });
  }
  const encoding = String(req.headers['content-encoding'] || 'identity').trim().toLowerCase();
  if (encoding !== 'identity') return reply(res, 415, { error: 'expected an uncompressed body' });

  readBody(req, MAX_BODY, (status, text) => {
    if (status) return reply(res, status, { error: `the body is over ${MAX_BODY} bytes` });
    let body;
    try {
      body = JSON.parse(text);
    } catch (_) {
      return reply(res, 400, { error: 'not valid JSON' });
    }

    const events = urlPath === '/api/events';
    const checked = events ? checkBatch(body) : checkForget(body);
    if (checked.error) return reply(res, 400, { error: checked.error });
    if (!store) {
      return reply(res, 503, { error: 'usage data is switched off on this server' }, { 'Retry-After': '3600' });
    }

    const work = events ? store.insertEvents(checked.rows) : store.forget(checked.installId);
    work.then(
      () => reply(res, 202, events ? { ok: true, accepted: checked.rows.length } : { ok: true }),
      (err) => {
        log.error(`usage data: ${events ? 'storing a batch' : 'forgetting an install'} failed (${describe(err)})`);
        reply(res, 503, { error: 'the database is unavailable' }, { 'Retry-After': '60' });
      });
  });
}

// The server. `store` is where usage data goes (analytics/store.js; null: nowhere, and /api answers 503).
function createServer(options = {}) {
  const { store = null, limiter = new RateLimiter(), log = console, canonicalHost = CANONICAL_HOST } = options;
  return http.createServer((req, res) => {
    const urlPath = (req.url || '/').split('?')[0];

    // before the www redirect: an app's POST shouldn't be bounced around
    if (urlPath === '/api' || urlPath.startsWith('/api/')) return api(req, res, urlPath, { store, limiter, log });

    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8', Allow: 'GET, HEAD' });
      return res.end('Method not allowed');
    }

    const host = String(req.headers.host || '').split(':')[0].toLowerCase();
    if (canonicalHost && host === 'www.' + canonicalHost) {
      // (a path, never the absolute or "*" forms a request may also name, so the address stays on this site)
      const target = (req.url || '/').startsWith('/') ? req.url : '/';
      res.writeHead(301, { Location: 'https://' + canonicalHost + target, 'Cache-Control': 'public, max-age=86400' });
      return res.end();
    }

    const file = resolve(req.url || '/');
    if (!file) return notFound(req, res);

    fs.stat(file, (err, stat) => {
      if (!err && stat.isDirectory()) {
        // /covers -> /covers/ so relative links inside resolve. The address is made from the folder's own path, never
        // from the request's: "//other.site/x%2f%2e%2e%2f%2e%2e%2fcovers" resolves to the covers folder too, and sent
        // back as it came it would send the browser to other.site.
        const folder = path.relative(PUBLIC, file).split(path.sep).map(encodeURIComponent).join('/');
        res.writeHead(301, { Location: folder ? `/${folder}/` : '/' });
        return res.end();
      }
      if (err && path.extname(file) === '') {
        // /about -> /about.html, if there is one
        return send(req, res, 200, file + '.html');
      }
      send(req, res, 200, file);
    });
  });
}

if (require.main === module) {
  const store = openStore(process.env.DATABASE_URL);
  const server = createServer({ store });

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`epicaudiogames.com listening on http://0.0.0.0:${PORT}` +
      (CANONICAL_HOST ? ` (www.${CANONICAL_HOST} redirects to ${CANONICAL_HOST})` : ''));
    console.log(store ? 'usage data: to Postgres' : 'usage data: no DATABASE_URL, so /api answers 503');
  });

  // The table is made on start (or on the first batch, if the database was down), and rows older than 13 months
  // are deleted then and once a day.
  const prune = () => store.prune().then(
    (n) => console.log(`usage data: table ready; ${n} rows older than 13 months deleted`),
    (err) => console.error(`usage data: making the table or deleting old rows failed (${describe(err)})`));
  if (store) {
    prune();
    setInterval(prune, DAY).unref();
  }

  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => server.close(() => {
      Promise.resolve(store && store.close()).finally(() => process.exit(0));
    }));
  }
}

module.exports = { createServer, RateLimiter, MAX_BODY };
