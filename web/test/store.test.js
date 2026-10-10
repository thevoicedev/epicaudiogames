// analytics/store.js: the Postgres store's SQL against a stand-in for pg's Pool, and the memory store. With
// TEST_DATABASE_URL set to a scratch database, the Postgres store and analytics/views.sql are tried on a real one
// too: it gets the events table and the report views, and rows under a test install id that it deletes again.
// Run with `node --test web/test/`.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { PostgresStore, MemoryStore, openStore, sslFor, COLUMNS, SCHEMA } = require('../analytics/store');
const { checkBatch } = require('../analytics/whitelist');

const SMOKE = JSON.parse(fs.readFileSync(path.join(__dirname, 'smoke-events.json'), 'utf8'));
const ROWS = checkBatch(SMOKE).rows;
const INSTALL = '00000000-0000-4000-8000-000000000001';
const RAILWAY = 'postgresql://postgres:secret@postgres.railway.internal:5432/railway';
const quiet = { error() {} };

// pg's Pool, as far as the store uses it: keeps its config and every query, and answers with answer().
class FakePool {
  constructor(config) {
    this.config = config;
    this.queries = [];
    this.listeners = {};
    this.answer = () => ({ rowCount: 0, rows: [] });
  }

  on(event, listener) {
    this.listeners[event] = listener;
  }

  async query(text, params) {
    this.queries.push({ text, params });
    return this.answer(text, params);
  }

  async end() {
    this.ended = true;
  }
}

function fakeStore(url = RAILWAY, options = {}) {
  let pool;
  const Pool = class extends FakePool {
    constructor(config) {
      super(config);
      pool = this;
    }
  };
  const store = new PostgresStore(url, Object.assign({ Pool, log: quiet }, options));
  return { store, pool };
}

test('the first use makes the table, once; a batch is one insert with every value a parameter', async () => {
  const { store, pool } = fakeStore();
  await store.insertEvents(ROWS);
  await store.insertEvents(ROWS.slice(0, 2));
  assert.equal(pool.queries.length, 3);
  assert.equal(pool.queries[0].text, SCHEMA);

  const insert = pool.queries[1];
  const last = ROWS.length * COLUMNS.length;
  assert.ok(insert.text.startsWith(`insert into events (${COLUMNS.join(', ')}) values ($1, $2, $3, `));
  assert.ok(insert.text.includes(`, $${last})`) && !insert.text.includes(`$${last + 1}`));
  assert.ok(insert.text.endsWith(' on conflict (install_id, session_id, seq) do nothing'));
  assert.equal(insert.params.length, last);
  assert.deepEqual(insert.params.slice(0, COLUMNS.length), [INSTALL, '00000000-0000-4000-8000-000000000002', 0,
    'app_open', '{"cold":true,"first":true}', '2026-10-09T09:41:00.000Z', '1.0', '3', 'android', '15', 'en-GB',
    'phone']);
  // nothing the apps sent is ever part of the SQL itself
  assert.doesNotMatch(insert.text, /app_open|alien|android|phone|en-GB|00000000/);
  assert.equal(pool.queries[2].params.length, 2 * COLUMNS.length);
});

test('the table has a column for every common field, form_factor last, also in a table made before it', () => {
  assert.equal(COLUMNS.at(-1), 'form_factor');
  const created = /create table if not exists events \(([\s\S]*?)\n\);/.exec(SCHEMA)[1];
  const names = created.split(',\n').map((line) => line.trim().split(/\s+/)[0]);
  assert.deepEqual(names, ['id', 'received_at', ...COLUMNS]);
  assert.match(SCHEMA, /^alter table events add column if not exists form_factor text;$/m);
});

test('a table that couldn\'t be made (the database was down) is tried again next time', async () => {
  const { store, pool } = fakeStore();
  let down = true;
  pool.answer = (text) => {
    if (down) throw Object.assign(new Error('connect ECONNREFUSED 10.0.0.1:5432'), { code: 'ECONNREFUSED' });
    return { rowCount: 0, rows: [] };
  };
  await assert.rejects(store.insertEvents(ROWS), /ECONNREFUSED/);
  down = false;
  await store.insertEvents(ROWS);
  assert.deepEqual(pool.queries.map((q) => (q.text === SCHEMA ? 'schema' : q.text.split(' ')[0])),
    ['schema', 'schema', 'insert']);
});

test('forget deletes by install id, and prune by age', async () => {
  const { store, pool } = fakeStore();
  pool.answer = () => ({ rowCount: 19, rows: [] });
  assert.equal(await store.forget(INSTALL), 19);
  assert.deepEqual(pool.queries[1], { text: 'delete from events where install_id = $1', params: [INSTALL] });
  assert.equal(await store.prune(), 19);
  assert.equal(pool.queries[2].text, "delete from events where received_at < now() - interval '13 months'");
});

test('the pool: no TLS on Railway\'s private network, a limit on waiting, and an idle connection lost is only logged',
  async () => {
    const logged = [];
    const { store, pool } = fakeStore(RAILWAY, { log: { error: (line) => logged.push(line) } });
    assert.equal(pool.config.connectionString, RAILWAY);
    assert.equal(pool.config.ssl, false);
    assert.equal(pool.config.connectionTimeoutMillis, 5000);
    pool.listeners.error(Object.assign(new Error('terminating connection due to administrator command'),
      { code: '57P01' }));
    assert.deepEqual(logged, ['usage data: lost an idle database connection (SQLSTATE 57P01)']);
    await store.close();
    assert.ok(pool.ended);
  });

test('TLS: off on Railway\'s private network and this machine; on, without checking the certificate, elsewhere', () => {
  assert.equal(sslFor(RAILWAY), false);
  assert.equal(sslFor('postgres://u:p@localhost:5432/x'), false);
  assert.equal(sslFor('postgres://u:p@127.0.0.1/x'), false);
  assert.equal(sslFor('postgres://u:p@[::1]:5432/x'), false);
  assert.deepEqual(sslFor('postgresql://u:p@gondola.proxy.rlwy.net:12345/railway'), { rejectUnauthorized: false });
  assert.equal(sslFor('postgresql://u:p@gondola.proxy.rlwy.net:12345/railway?sslmode=disable'), undefined);
  assert.equal(sslFor('not a url'), undefined);
});

test('openStore: nothing without a DATABASE_URL', async () => {
  assert.equal(openStore(undefined, quiet), null);
  assert.equal(openStore('', quiet), null);
  const store = openStore(RAILWAY, quiet);
  assert.ok(store instanceof PostgresStore);
  await store.close(); // it never connected
});

test('the memory store keeps a batch sent twice once, forgets an install, and prunes by age', async () => {
  const store = new MemoryStore();
  await store.insertEvents(ROWS);
  await store.insertEvents(ROWS);
  assert.equal(store.rows.length, 19);
  store.rows[0].received_at = '2025-01-01T00:00:00.000Z';
  assert.equal(await store.prune(), 1);
  assert.equal(await store.forget(INSTALL), 18);
  assert.equal(await store.forget(INSTALL), 0);
  assert.equal(store.rows.length, 0);
});

// The reports analytics/views.sql makes, as it names them.
const VIEWS_SQL = fs.readFileSync(path.join(__dirname, '..', 'analytics', 'views.sql'), 'utf8');
const REPORT_VIEWS = [...VIEWS_SQL.matchAll(/^create view (report_\w+)/gm)].map((m) => m[1]);

test('every report in views.sql is one tools/analytics_report.py prints', () => {
  assert.ok(REPORT_VIEWS.includes('report_funnel') && REPORT_VIEWS.includes('report_devices'));
  // its REPORTS: "name": ("report_view", "what it shows", limit)
  const tool = fs.readFileSync(path.join(__dirname, '..', '..', 'tools', 'analytics_report.py'), 'utf8');
  const printed = [...tool.matchAll(/^ {4}"\w+": \("(report_\w+)",/gm)].map((m) => m[1]);
  assert.deepEqual([...printed].sort(), [...REPORT_VIEWS].sort());
});

const DATABASE = process.env.TEST_DATABASE_URL;
const TEST_INSTALL = '00000000-0000-4000-8000-0000000000ff';

test('on a real Postgres: the table, a batch (twice), the report views, forget and prune',
  { skip: !DATABASE && 'TEST_DATABASE_URL is not set' }, async () => {
    const { Pool } = require('pg');
    const store = new PostgresStore(DATABASE, { Pool, max: 1, log: quiet });
    const query = async (text, params) => (await store.pool.query(text, params)).rows;
    const count = async (id) => {
      return Number((await query('select count(*) from events where install_id = $1', [id]))[0].count);
    };
    // the smoke batch under an install the views don't leave out, so they have something to count
    const rows = ROWS.map((row) => Object.assign({}, row, { install_id: TEST_INSTALL }));
    try {
      await store.forget(TEST_INSTALL); // makes the table too
      await store.forget(INSTALL);
      const empty = Number((await query('select count(*) from events'))[0].count) === 0;

      await store.insertEvents(rows);
      await store.insertEvents(rows);
      await store.insertEvents(ROWS);
      assert.equal(await count(TEST_INSTALL), 19);
      assert.equal(await count(INSTALL), 19);

      const columns = await query(`select column_name from information_schema.columns
        where table_name = 'events' and table_schema = current_schema() order by ordinal_position`);
      assert.deepEqual(columns.map((c) => c.column_name), ['id', 'received_at', ...COLUMNS]);
      const stored = await query('select * from events where install_id = $1 order by seq', [TEST_INSTALL]);
      assert.deepEqual(stored[12].props, SMOKE[12].props);
      assert.equal(stored[0].ts.toISOString(), SMOKE[0].ts);
      assert.equal(stored[0].session_id, SMOKE[0].session_id);

      await store.pool.query(VIEWS_SQL);
      const reports = {};
      for (const view of REPORT_VIEWS) reports[view] = await query(`select * from ${view}`);
      const smokeLeftOut = await query('select count(*) from usage_events where install_id = $1', [INSTALL]);
      assert.equal(Number(smokeLeftOut[0].count), 0);

      if (empty) {
        // nothing else in the database: the reports are exactly the test install's one session
        assert.equal(reports.report_events.length, 19);
        assert.deepEqual(reports.report_funnel.map((r) => [r.step, Number(r.installs), Number(r.pct_of_opened)]), [
          ['Opened the app', 1, 100], ['Finished the intro', 1, 100], ['Finished or skipped the welcome', 1, 100],
          ['Opened a game', 1, 100], ['Finished a chapter', 1, 100], ['Opened the shop', 1, 100],
          ['Bought a pack', 1, 100]]);
        const game = reports.report_games[0];
        assert.equal(reports.report_games.length, 1);
        assert.deepEqual([game.game, game.players, game.finished_a_chapter, game.next_chapters, game.restarts,
          game.errors, game.answers_spoken, game.answers_typed, game.answers_tapped].map(String),
        ['alien-customs', '1', '1', '1', '1', '1', '9', '3', '2']);
        assert.deepEqual(reports.report_chapter_ends.map((r) => [r.game, r.kind, r.node, Number(r.installs)]),
          [['alien-customs', 'chapter', 'L1_win', 1]]);
        assert.deepEqual(reports.report_drop_off.map((r) => [r.node, Number(r.leaves), Number(r.avg_seconds)]),
          [['L1_start', 1, 312]]);
        assert.deepEqual(reports.report_shop.map((r) => [r.source, Number(r.views), Number(r.purchases_started),
          Number(r.purchased)]), [['locked_end', 1, 1, 1]]);
        assert.equal(reports.report_retention.length, 1);
        assert.equal(Number(reports.report_retention[0].installs), 1);
        assert.deepEqual(reports.report_devices.map((r) => [r.platform, r.form_factor, Number(r.installs),
          Number(r.events)]), [['android', 'phone', 1, 19]]);
      }

      assert.equal(await store.forget(TEST_INSTALL), 19);
      assert.equal(await store.forget(INSTALL), 19);
      assert.equal(await count(TEST_INSTALL), 0);
      assert.ok((await store.prune()) >= 0);
    } finally {
      await store.forget(TEST_INSTALL).catch(() => {});
      await store.close();
    }
  });

// The events table as the first version of the server made it, before form_factor.
const FIRST_TABLE = `create table events (id bigserial primary key, received_at timestamptz not null default now(),
  install_id uuid not null, session_id uuid not null, seq int not null, name text not null, props jsonb not null,
  ts timestamptz, app_version text, build text, platform text, os_version text, lang text)`;

test('on a real Postgres: a table made before form_factor gets the column, last, as a new table has it',
  { skip: !DATABASE && 'TEST_DATABASE_URL is not set' }, async () => {
    const { Pool } = require('pg');
    const pool = new Pool({ connectionString: DATABASE, ssl: sslFor(DATABASE), max: 1 });
    const client = await pool.connect();
    try {
      // in a schema of its own, in a transaction that's rolled back: the database's own events table isn't touched
      await client.query('begin');
      await client.query('create schema form_factor_upgrade');
      await client.query('set local search_path to form_factor_upgrade');
      await client.query(FIRST_TABLE);
      await client.query(SCHEMA);
      await client.query(SCHEMA); // and again, as on every start: nothing changes
      const columns = (await client.query(`select column_name from information_schema.columns
        where table_name = 'events' and table_schema = 'form_factor_upgrade' order by ordinal_position`)).rows;
      assert.deepEqual(columns.map((c) => c.column_name), ['id', 'received_at', ...COLUMNS]);
    } finally {
      await client.query('rollback').catch(() => {});
      client.release();
      await pool.end();
    }
  });
