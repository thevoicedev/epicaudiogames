// The usage-data API's smoke test, for after a deploy: sends the payloads in web/test/ to a server, checks each
// answer, and forgets the smoke install again.
//
//   node web/scripts/smoke.js https://epicaudiogames.com
//   node web/scripts/smoke.js http://localhost:3000 --keep     # leave the smoke rows, to look at with db-check.js
//
// GET → 405; text/plain → 415; an event that isn't in the whitelist → 400; every event (smoke-events.json, under the
// reserved install 00000000-0000-4000-8000-000000000001), sent with the apps' user agent → 202 (so Cloudflare lets
// the apps through); forget → 202; then a burst that has to meet the rate limit (429) within 30 requests, which holds
// this machine up for a few seconds. Exits with 1 if anything isn't as it should be.
'use strict';

const fs = require('fs');
const path = require('path');

const TEST = path.join(__dirname, '..', 'test');
const read = (name) => fs.readFileSync(path.join(TEST, name), 'utf8');
const JSON_TYPE = 'application/json';
let failed = false;

async function check(label, expected, url, { method = 'POST', type = JSON_TYPE, body, agent } = {}) {
  const headers = {};
  if (type) headers['Content-Type'] = type;
  if (agent) headers['User-Agent'] = agent;
  let status;
  let text = '';
  try {
    const res = await fetch(url, { method, headers, body });
    status = res.status;
    text = await res.text();
  } catch (err) {
    text = err.cause ? err.cause.message : err.message;
  }
  const ok = status === expected;
  if (!ok) failed = true;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}: ${status || 'no answer'}` +
    (ok ? '' : ` (expected ${expected}) ${text.slice(0, 200)}`) +
    (status === 503 ? '  <- the server has no database (DATABASE_URL), or it is down' : ''));
  return status;
}

async function main() {
  const base = (process.argv[2] || '').replace(/\/+$/, '');
  const keep = process.argv.includes('--keep');
  if (!/^https?:\/\//.test(base)) {
    console.error('usage: node web/scripts/smoke.js <https://epicaudiogames.com | http://localhost:3000> [--keep]');
    process.exit(2);
  }
  const events = `${base}/api/events`;
  const forget = `${base}/api/forget`;

  await check('GET /api/events', 405, events, { method: 'GET', type: null });
  await check('POST /api/events as text/plain', 415, events, { type: 'text/plain', body: read('smoke-events.json') });
  await check('POST an event that is not in the whitelist', 400, events, { body: read('smoke-unknown.json') });
  await check('POST every event, as the Android app', 202, events,
    { body: read('smoke-events.json'), agent: 'EpicAudioGames/1.0 (android)' });
  await check('POST them again, as the iPhone app (stored once)', 202, events,
    { body: read('smoke-events.json'), agent: 'EpicAudioGames/1.0 (ios)' });
  if (keep) {
    console.log('     (kept the smoke rows: node web/scripts/db-check.js 00000000-0000-4000-8000-000000000001)');
  } else {
    await check('POST /api/forget for the smoke install', 202, forget, { body: read('smoke-forget.json') });
  }

  // the rate limit: requests the server turns away before reading them still count
  let limited = false;
  for (let i = 0; i < 30 && !limited; i++) {
    const res = await fetch(events, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: 'x' });
    limited = res.status === 429;
  }
  console.log(`${limited ? 'ok  ' : 'FAIL'} a burst meets the rate limit: ` +
    (limited ? '429' : 'no 429 in 30 requests'));
  if (!limited) failed = true;
  process.exit(failed ? 1 : 0);
}

main();
