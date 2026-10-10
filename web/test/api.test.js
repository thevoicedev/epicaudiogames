// The /api endpoints (and the site next to them) through a real server on a free port, with usage data kept in memory.
// Run with `node --test web/test/`.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { createServer, RateLimiter, MAX_BODY } = require('../server');
const { MemoryStore, COLUMNS } = require('../analytics/store');

const SMOKE = fs.readFileSync(path.join(__dirname, 'smoke-events.json'), 'utf8');
const UNKNOWN = fs.readFileSync(path.join(__dirname, 'smoke-unknown.json'), 'utf8');
const FORGET = fs.readFileSync(path.join(__dirname, 'smoke-forget.json'), 'utf8');
const INSTALL = '00000000-0000-4000-8000-000000000001';
const OTHER = '00000000-0000-4000-8000-000000000003';
const JSON_TYPE = { 'Content-Type': 'application/json' };

// A server for test `t`, closed when it ends (passed or not): usage data in `store` (a MemoryStore unless given; null
// for none), a rate limit that doesn't get in the way unless given, and what it logs in `logged`.
async function start(t, options = {}) {
  const logged = [];
  const log = { error: (line) => logged.push(line), log: (line) => logged.push(line) };
  const store = 'store' in options ? options.store : new MemoryStore();
  const limiter = options.limiter || new RateLimiter({ perMinute: 60000, burst: 1000 });
  const server = createServer({ store, limiter, log, canonicalHost: 'epicaudiogames.com' });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const { port } = server.address();
  return {
    store, logged,
    request: (opts) => request(port, opts),
    post: (urlPath, body, headers = JSON_TYPE) => request(port, { method: 'POST', path: urlPath, headers, body }),
  };
}

// One HTTP request with exactly these headers. `body` is a string, or an array of strings to send chunked.
function request(port, { method = 'GET', path: urlPath = '/', headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const chunked = Array.isArray(body);
    const all = Object.assign({}, headers);
    if (body !== undefined && !chunked) all['Content-Length'] = Buffer.byteLength(body);
    const req = http.request({ host: '127.0.0.1', port, method, path: urlPath, headers: all, agent: false }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json;
        try {
          json = JSON.parse(text);
        } catch (_) { /* a page, not JSON */ }
        resolve({ status: res.statusCode, headers: res.headers, text, json });
      });
    });
    req.on('error', reject);
    if (chunked) for (const part of body) req.write(part);
    else if (body !== undefined) req.write(body);
    req.end();
  });
}

function assertApiHeaders(res) {
  assert.equal(res.headers['cache-control'], 'no-store');
  assert.equal(res.headers['content-type'], 'application/json; charset=utf-8');
  assert.equal(res.headers['x-content-type-options'], 'nosniff');
}

test('the smoke batch goes through to the store: 202, and the rows are what the app sent', async (t) => {
  const s = await start(t);
  const res = await s.post('/api/events', SMOKE);
  assert.equal(res.status, 202);
  assert.deepEqual(res.json, { ok: true, accepted: 19 });
  assertApiHeaders(res);

  assert.equal(s.store.rows.length, 19);
  const sent = JSON.parse(SMOKE);
  s.store.rows.forEach((row, i) => {
    assert.deepEqual(Object.keys(row).sort(), ['id', 'received_at', ...COLUMNS].sort()); // nothing about the request
    assert.equal(row.name, sent[i].name);
    assert.deepEqual(row.props, sent[i].props);
    assert.equal(row.install_id, INSTALL);
    assert.equal(row.ts, sent[i].ts);
  });
});

test('the kind of device is stored as the app sent it, and a device model is refused: 400', async (t) => {
  const s = await start(t);
  // the first smoke event with `changes` (a change to undefined leaves that field out), as a batch of one
  const one = (changes) => {
    const e = Object.assign(JSON.parse(SMOKE)[0], changes);
    for (const key of Object.keys(e)) if (e[key] === undefined) delete e[key];
    return JSON.stringify([e]);
  };
  assert.equal((await s.post('/api/events', SMOKE)).status, 202);
  assert.ok(s.store.rows.every((row) => row.form_factor === 'phone'));
  for (const [seq, kind] of [[100, 'tablet'], [101, 'desktop'], [102, 'watch']]) {
    assert.equal((await s.post('/api/events', one({ seq, form_factor: kind }))).status, 202, kind);
    assert.equal(s.store.rows.at(-1).form_factor, kind);
  }
  // an app version from before form_factor
  assert.equal((await s.post('/api/events', one({ seq: 103, form_factor: undefined }))).status, 202);
  assert.equal(s.store.rows.at(-1).form_factor, null);

  for (const model of ['iPad Pro (12.9-inch)', 'iPad13,8', 'Pixel 9', 'SM-S921B']) {
    const res = await s.post('/api/events', one({ seq: 104, form_factor: model }));
    assert.equal(res.status, 400, model);
    assert.deepEqual(res.json, { error: 'events[0]: "form_factor" has the wrong type' });
  }
  assert.equal(s.store.rows.length, 23);
  assert.ok(s.store.rows.every((row) => ['phone', 'tablet', 'desktop', 'watch', null].includes(row.form_factor)));
});

test('a batch sent twice is stored once', async (t) => {
  const s = await start(t);
  assert.equal((await s.post('/api/events', SMOKE)).status, 202);
  assert.equal((await s.post('/api/events', SMOKE)).status, 202);
  assert.equal(s.store.rows.length, 19);
});

test('a refused batch stores nothing: 400 with the reason', async (t) => {
  const s = await start(t);
  let res = await s.post('/api/events', UNKNOWN);
  assert.equal(res.status, 400);
  assert.deepEqual(res.json, { error: 'events[0]: unknown event "screen_reader_on"' });
  assertApiHeaders(res);

  const batch = JSON.parse(SMOKE);
  batch[5].props.topic = 'voice';
  res = await s.post('/api/events', JSON.stringify(batch));
  assert.equal(res.status, 400);
  assert.match(res.json.error, /^events\[5\]: help_viewed has no property "topic"$/);

  for (const body of ['', '{', 'null', '{}', '[]', '"x"']) {
    res = await s.post('/api/events', body);
    assert.equal(res.status, 400, body);
  }
  assert.equal(s.store.rows.length, 0);
});

test('more than 100 events: 400', async (t) => {
  const s = await start(t);
  const one = JSON.parse(SMOKE)[0];
  const batch = Array.from({ length: 101 }, (_, seq) => Object.assign({}, one, { seq }));
  const res = await s.post('/api/events', JSON.stringify(batch));
  assert.equal(res.status, 400);
  assert.match(res.json.error, /expected 1 to 100 events, not 101/);
  assert.equal(s.store.rows.length, 0);
});

test(`a body over ${MAX_BODY} bytes: 413, whether it says its length or is sent in chunks`, async (t) => {
  const s = await start(t);
  const big = JSON.stringify([{ name: 'x'.repeat(MAX_BODY) }]);
  let res = await s.post('/api/events', big);
  assert.equal(res.status, 413);
  assertApiHeaders(res);

  const chunks = Array.from({ length: 20 }, () => ' '.repeat(8 * 1024));
  res = await s.post('/api/events', ['[', ...chunks, ']'], { 'Content-Type': 'application/json' });
  assert.equal(res.status, 413);

  // the connection is still good for the next one
  assert.equal((await s.post('/api/events', SMOKE)).status, 202);
  // and a body of exactly the limit is read (it's whitespace around a good batch)
  res = await s.post('/api/events', SMOKE + ' '.repeat(MAX_BODY - Buffer.byteLength(SMOKE)));
  assert.equal(res.status, 202);
});

test('not JSON, or compressed: 415', async (t) => {
  const s = await start(t);
  const types = [undefined, 'text/plain', 'application/x-www-form-urlencoded', 'application/json-patch+json',
    'application/json; charset=latin1', 'text/json'];
  for (const type of types) {
    const res = await s.post('/api/events', SMOKE, type ? { 'Content-Type': type } : {});
    assert.equal(res.status, 415, String(type));
    assertApiHeaders(res);
  }
  let res = await s.post('/api/events', SMOKE, { 'Content-Type': 'application/json', 'Content-Encoding': 'gzip' });
  assert.equal(res.status, 415);
  res = await s.post('/api/forget', FORGET, { 'Content-Type': 'text/plain' });
  assert.equal(res.status, 415);
  assert.equal(s.store.rows.length, 0);

  for (const type of ['application/json; charset=UTF-8', 'Application/JSON;charset=utf-8']) {
    res = await s.post('/api/events', SMOKE, { 'Content-Type': type });
    assert.equal(res.status, 202, type);
  }
});

test('anything but POST on /api: 405, Allow: POST', async (t) => {
  const s = await start(t);
  for (const method of ['GET', 'HEAD', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
    for (const urlPath of ['/api/events', '/api/forget', '/api', '/api/', '/api/nope']) {
      const res = await s.request({ method, path: urlPath });
      assert.equal(res.status, 405, `${method} ${urlPath}`);
      assert.equal(res.headers.allow, 'POST');
      assert.equal(res.headers['cache-control'], 'no-store');
    }
  }
});

test('POST to an endpoint there isn\'t: 404', async (t) => {
  const s = await start(t);
  for (const urlPath of ['/api', '/api/', '/api/nope', '/api/events/', '/api/events/x']) {
    const res = await s.post(urlPath, SMOKE);
    assert.equal(res.status, 404, urlPath);
    assertApiHeaders(res);
  }
  // (a query string doesn't matter)
  assert.equal((await s.post('/api/events?v=1', SMOKE)).status, 202);
});

test('the rate limit: a burst, then 429 with Retry-After, one bucket per IP address', async (t) => {
  let now = 1000000;
  const s = await start(t, { limiter: new RateLimiter({ perMinute: 60, burst: 3, now: () => now }) });
  const from = (ip) => Object.assign({ 'CF-Connecting-IP': ip }, JSON_TYPE);
  for (let i = 0; i < 3; i++) assert.equal((await s.post('/api/events', SMOKE, from('203.0.113.1'))).status, 202);
  let res = await s.post('/api/events', SMOKE, from('203.0.113.1'));
  assert.equal(res.status, 429);
  assert.equal(res.headers['retry-after'], '1');
  assertApiHeaders(res);
  assert.equal((await s.post('/api/forget', FORGET, from('203.0.113.1'))).status, 429); // the same bucket

  // someone else isn't held up
  assert.equal((await s.post('/api/events', SMOKE, from('198.51.100.7'))).status, 202);
  // without Cloudflare's header, Railway's X-Real-IP, then the socket's own address
  const railway = Object.assign({ 'X-Real-IP': '192.0.2.5' }, JSON_TYPE);
  for (let i = 0; i < 3; i++) assert.equal((await s.post('/api/events', SMOKE, railway)).status, 202);
  assert.equal((await s.post('/api/events', SMOKE, railway)).status, 429);
  for (let i = 0; i < 3; i++) assert.equal((await s.post('/api/events', SMOKE)).status, 202);
  assert.equal((await s.post('/api/events', SMOKE)).status, 429);

  // a second later there's a request's worth again
  now += 1000;
  assert.equal((await s.post('/api/events', SMOKE, from('203.0.113.1'))).status, 202);
  res = await s.post('/api/events', SMOKE, from('203.0.113.1'));
  assert.equal(res.status, 429);
  // (and the IP addresses went nowhere but the limiter)
  assert.deepEqual(s.logged, []);
});

test('the rate limiter refills, and forgets the buckets that have filled up again', () => {
  let now = 0;
  const limiter = new RateLimiter({ perMinute: 60, burst: 20, now: () => now, maxClients: 5 });
  for (let i = 0; i < 20; i++) assert.equal(limiter.take('a'), 0);
  assert.equal(limiter.take('a'), 1);
  now += 10000;
  for (let i = 0; i < 10; i++) assert.equal(limiter.take('a'), 0);
  assert.equal(limiter.take('a'), 1);

  assert.equal(limiter.take('b'), 0);
  now += 61000; // both full again by now
  limiter.take('c');
  assert.deepEqual([...limiter.buckets.keys()], ['c']);

  // a flood of addresses can't grow the map past maxClients
  for (let i = 0; i < 50; i++) limiter.take(`flood-${i}`);
  assert.ok(limiter.buckets.size <= 5);
});

test('forget deletes that install\'s rows and no one else\'s: 202, also when there\'s nothing', async (t) => {
  const s = await start(t);
  const other = SMOKE.split(INSTALL).join(OTHER);
  assert.equal((await s.post('/api/events', SMOKE)).status, 202);
  assert.equal((await s.post('/api/events', other)).status, 202);
  assert.equal(s.store.rows.length, 38);

  let res = await s.post('/api/forget', FORGET);
  assert.equal(res.status, 202);
  assert.deepEqual(res.json, { ok: true });
  assertApiHeaders(res);
  assert.equal(s.store.rows.length, 19);
  assert.ok(s.store.rows.every((row) => row.install_id === OTHER));

  res = await s.post('/api/forget', FORGET);
  assert.equal(res.status, 202);
  res = await s.post('/api/forget', JSON.stringify({ install_id: OTHER.toUpperCase() }));
  assert.equal(res.status, 202);
  assert.equal(s.store.rows.length, 0);
});

test('forget with anything but an install id: 400', async (t) => {
  const s = await start(t);
  await s.post('/api/events', SMOKE);
  for (const body of ['{}', '[]', '{"install_id": "nope"}', `{"install_id": "${INSTALL}", "all": true}`, 'x']) {
    const res = await s.post('/api/forget', body);
    assert.equal(res.status, 400, body);
  }
  assert.equal(s.store.rows.length, 19);
});

test('without a database: 503 (so the apps send it later), and the site works as ever', async (t) => {
  const s = await start(t, { store: null });
  let res = await s.post('/api/events', SMOKE);
  assert.equal(res.status, 503);
  assert.ok(Number(res.headers['retry-after']) > 0);
  assertApiHeaders(res);
  assert.equal((await s.post('/api/forget', FORGET)).status, 503);
  // a bad batch is still a 400: the app can drop it rather than keep sending it
  assert.equal((await s.post('/api/events', UNKNOWN)).status, 400);

  for (const urlPath of ['/', '/privacy', '/support', '/accessibility', '/privacy.html', '/sitemap.xml']) {
    res = await s.request({ path: urlPath });
    assert.equal(res.status, 200, urlPath);
  }
  res = await s.request({ path: '/accessibility' });
  assert.equal(res.headers['content-type'], 'text/html; charset=utf-8');
  assert.equal(res.headers['cache-control'], 'no-cache');
});

test('a database that fails: 503, and the log says why without a word of the request', async (t) => {
  const error = (message, code) => Object.assign(new Error(message), { code });
  const failing = {
    insertEvents: () => Promise.reject(error('connect ECONNREFUSED 10.0.0.1:5432', 'ECONNREFUSED')),
    forget: () => Promise.reject(error('relation "events" does not exist', '42P01')),
  };
  const s = await start(t, { store: failing });
  const res = await s.post('/api/events', SMOKE, Object.assign({ 'CF-Connecting-IP': '203.0.113.1' }, JSON_TYPE));
  assert.equal(res.status, 503);
  assert.equal(res.headers['retry-after'], '60');
  assert.equal((await s.post('/api/forget', FORGET)).status, 503);
  assert.deepEqual(s.logged, [
    'usage data: storing a batch failed (ECONNREFUSED)',
    'usage data: forgetting an install failed (SQLSTATE 42P01)',
  ]);
});

test('the site: the www redirect as before, the API on any host, and no more /packs', async (t) => {
  const s = await start(t);
  let res = await s.request({ path: '/support', headers: { Host: 'www.epicaudiogames.com' } });
  assert.equal(res.status, 301);
  assert.equal(res.headers.location, 'https://epicaudiogames.com/support');

  res = await s.post('/api/events', SMOKE, Object.assign({ Host: 'www.epicaudiogames.com' }, JSON_TYPE));
  assert.equal(res.status, 202);

  for (const urlPath of ['/packs/the-werewolf-stories-1.zip', '/packs', '/packs/']) {
    res = await s.request({ path: urlPath });
    assert.equal(res.status, 404, urlPath);
  }
  res = await s.request({ method: 'POST', path: '/privacy' });
  assert.equal(res.status, 405);
  assert.equal(res.headers.allow, 'GET, HEAD');
  res = await s.request({ path: '/../server.js' });
  assert.equal(res.status, 404);
});

test('a folder\'s redirect stays on this site, whatever path the folder was reached by', async (t) => {
  const s = await start(t);
  // the last three name the covers folder too, and sent back as they came would take a browser to another site
  for (const urlPath of ['/covers', '/covers?v=1', '//covers', '//evil.example/x%2f%2e%2e%2f%2e%2e%2fcovers',
    '/\\evil.example/../covers']) {
    const res = await s.request({ path: urlPath });
    assert.equal(res.status, 301, urlPath);
    assert.equal(res.headers.location, '/covers/', urlPath);
  }
  const res = await s.request({ path: '//evil.example/', headers: { Host: 'www.epicaudiogames.com' } });
  assert.equal(new URL(res.headers.location).host, 'epicaudiogames.com');
});
