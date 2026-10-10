// Where usage data is kept: a Postgres database (on Railway, the Postgres service next to the web one), or memory, for
// the tests. Both do the same three things:
//   insertEvents(rows)  stores a batch checked by whitelist.js, all of it or none of it. An event that comes twice
//                       (the same install, session and seq: an app sending a batch again after its answer was lost)
//                       is kept once.
//   forget(installId)   deletes every row of that install; resolves to how many there were
//   prune()             deletes rows received more than 13 months ago; resolves to how many there were
// The table has no column for an IP address or anything else about the request: only what the apps send.
'use strict';

// The events table's columns that come from a row, in the order the insert names them (and the table has them).
const COLUMNS = ['install_id', 'session_id', 'seq', 'name', 'props', 'ts', 'app_version', 'build', 'platform',
  'os_version', 'lang', 'form_factor'];

// Made the first time the store is used. events_once is what lets a batch sent twice be stored once. form_factor came
// after the first version of the table, so a table made before it gets the column from the alter; it's the last
// column either way, so the two have their columns in the same order.
const SCHEMA = `
create table if not exists events (
  id bigserial primary key,
  received_at timestamptz not null default now(),
  install_id uuid not null,
  session_id uuid not null,
  seq int not null,
  name text not null,
  props jsonb not null,
  ts timestamptz,
  app_version text,
  build text,
  platform text,
  os_version text,
  lang text,
  form_factor text
);
alter table events add column if not exists form_factor text;
create index if not exists events_name_ts on events (name, ts);
create index if not exists events_install_ts on events (install_id, ts);
create unique index if not exists events_once on events (install_id, session_id, seq);
`;

const RETENTION = '13 months';

// What went wrong talking to the database, for the log: a Postgres error's code, or the connection's own error. Never
// the error's detail, which can quote the values of a row.
function describe(err) {
  if (/^[0-9A-Z]{5}$/.test(err.code || '')) return `SQLSTATE ${err.code}`;
  return err.code || err.message;
}

// TLS settings for a database URL. Railway's private network (postgres.railway.internal) and a database on this
// machine don't use it; anything else, such as the public proxy (*.proxy.rlwy.net), does, without checking the
// certificate (Railway's Postgres has a self-signed one). An sslmode in the URL wins.
function sslFor(url) {
  let host;
  try {
    const u = new URL(url);
    if (u.searchParams.has('sslmode')) return undefined;
    host = u.hostname;
  } catch (_) {
    return undefined;
  }
  const local = host.endsWith('.railway.internal') || ['localhost', '127.0.0.1', '[::1]'].includes(host);
  return local ? false : { rejectUnauthorized: false };
}

class PostgresStore {
  // Pool is pg's (passed in so the tests can watch the queries without a database).
  constructor(url, { Pool, max = 4, log = console } = {}) {
    this.log = log;
    this.pool = new Pool({
      connectionString: url,
      ssl: sslFor(url),
      max,
      connectionTimeoutMillis: 5000, // a database that's down gets the apps a 503 in seconds, not a hung request
      idleTimeoutMillis: 30000,
      statement_timeout: 10000,
    });
    // A connection that breaks while idle (the database restarting) mustn't take the website down with it.
    this.pool.on('error', (err) => log.error(`usage data: lost an idle database connection (${describe(err)})`));
    this.ready = null;
  }

  // Makes the table on first use, and tries again next time if that failed (the database may have been down).
  schema() {
    if (!this.ready) {
      this.ready = this.pool.query(SCHEMA).catch((err) => {
        this.ready = null;
        throw err;
      });
    }
    return this.ready;
  }

  async insertEvents(rows) {
    await this.schema();
    const params = [];
    const tuples = rows.map((row) => {
      const at = params.length;
      for (const column of COLUMNS) params.push(column === 'props' ? JSON.stringify(row.props) : row[column]);
      return '(' + COLUMNS.map((_, i) => '$' + (at + i + 1)).join(', ') + ')';
    });
    await this.pool.query(
      `insert into events (${COLUMNS.join(', ')}) values ${tuples.join(', ')} ` +
      'on conflict (install_id, session_id, seq) do nothing',
      params);
  }

  async forget(installId) {
    await this.schema();
    return (await this.pool.query('delete from events where install_id = $1', [installId])).rowCount;
  }

  async prune() {
    await this.schema();
    return (await this.pool.query(`delete from events where received_at < now() - interval '${RETENTION}'`)).rowCount;
  }

  close() {
    return this.pool.end();
  }
}

// The same, in memory: for the tests, and for trying the apps against a server on this machine.
class MemoryStore {
  constructor() {
    this.rows = [];
    this.nextId = 1;
  }

  async insertEvents(rows) {
    const key = (row) => `${row.install_id} ${row.session_id} ${row.seq}`;
    const seen = new Set(this.rows.map(key));
    const receivedAt = new Date().toISOString();
    for (const row of rows) {
      if (seen.has(key(row))) continue;
      seen.add(key(row));
      this.rows.push(Object.assign({ id: this.nextId++, received_at: receivedAt }, row));
    }
  }

  async forget(installId) {
    const before = this.rows.length;
    this.rows = this.rows.filter((row) => row.install_id !== installId);
    return before - this.rows.length;
  }

  async prune() {
    const cutoff = new Date();
    cutoff.setUTCMonth(cutoff.getUTCMonth() - 13);
    const before = this.rows.length;
    this.rows = this.rows.filter((row) => new Date(row.received_at) >= cutoff);
    return before - this.rows.length;
  }

  async close() {}
}

// The store for a DATABASE_URL, or null without one (the API then answers 503, and the site carries on as ever: it
// never depends on the database, so nothing here may stop the server starting).
function openStore(url, log = console) {
  if (!url) return null;
  try {
    return new PostgresStore(url, { Pool: require('pg').Pool, log });
  } catch (err) {
    log.error(err.code === 'MODULE_NOT_FOUND'
      ? 'usage data: DATABASE_URL is set, but the pg package is missing (npm install --prefix web)'
      : `usage data: can't use DATABASE_URL (${describe(err)})`);
    return null;
  }
}

module.exports = { PostgresStore, MemoryStore, openStore, sslFor, describe, COLUMNS, SCHEMA };
