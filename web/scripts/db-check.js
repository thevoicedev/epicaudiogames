// Looks at the usage-data table: its columns (to show there's no IP address, or anything else about a request, among
// them) and how many rows an install has, by event.
//
//   node web/scripts/db-check.js <install_id>
//   node web/scripts/db-check.js 00000000-0000-4000-8000-000000000001     # the smoke tests' install
//
// The database is DATABASE_PUBLIC_URL, else DATABASE_URL. From this machine that's the Postgres service's public URL
// (`railway run --service Postgres node web/scripts/db-check.js <id>` sets it; DATABASE_URL there is Railway's
// private address, which only works inside Railway). The URL is never printed: it holds the password.
'use strict';

const { Client } = require('pg');
const { sslFor, describe } = require('../analytics/store');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// A connection, with TLS if the database offers it (Railway's public proxy does) and without if it doesn't.
async function connect(url) {
  const tries = sslFor(url) ? [sslFor(url), false] : [sslFor(url)];
  for (const [i, ssl] of tries.entries()) {
    const client = new Client({ connectionString: url, ssl, connectionTimeoutMillis: 10000 });
    try {
      await client.connect();
      return client;
    } catch (err) {
      await client.end().catch(() => {});
      if (i === tries.length - 1 || !/does not support SSL/i.test(err.message)) throw err;
    }
  }
}

async function main() {
  const id = process.argv[2];
  const url = process.env.DATABASE_PUBLIC_URL || process.env.DATABASE_URL;
  if (!id || !UUID.test(id)) {
    console.error('usage: node web/scripts/db-check.js <install_id>   (with DATABASE_PUBLIC_URL or DATABASE_URL set)');
    process.exit(2);
  }
  if (!url) {
    console.error('Set DATABASE_PUBLIC_URL (the Postgres service\'s Variables tab on Railway), or run this with ' +
      '`railway run --service Postgres`.');
    process.exit(2);
  }

  const client = await connect(url);
  try {
    const columns = (await client.query(`select column_name, data_type from information_schema.columns
      where table_name = 'events' and table_schema = current_schema() order by ordinal_position`)).rows;
    if (!columns.length) {
      console.log('No events table yet: the server makes it when it starts with DATABASE_URL set.');
      return;
    }
    console.log('events columns:');
    for (const c of columns) console.log(`  ${c.column_name.padEnd(12)} ${c.data_type}`);
    const suspicious = columns.filter((c) => /(^|_)(ip|addr|address|host|agent|ua)($|_)/i.test(c.column_name));
    console.log(suspicious.length
      ? `!! columns that could hold something about the request: ${suspicious.map((c) => c.column_name).join(', ')}`
      : 'No column for an IP address, a user agent or anything else about the request.');

    const counts = (await client.query(`select name, count(*)::int as n, min(received_at) as first,
      max(received_at) as last from events where install_id = $1 group by name order by name`, [id.toLowerCase()])).rows;
    const total = counts.reduce((sum, r) => sum + r.n, 0);
    console.log(`\n${total} rows for ${id.toLowerCase()}` + (total ? ':' : ''));
    for (const r of counts) console.log(`  ${r.name.padEnd(20)} ${String(r.n).padStart(5)}`);
    if (total) {
      const first = new Date(Math.min(...counts.map((r) => r.first))).toISOString();
      const last = new Date(Math.max(...counts.map((r) => r.last))).toISOString();
      console.log(`received from ${first} to ${last}`);
    }
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error(`db-check: ${describe(err)}${err.code && err.message ? ': ' + err.message.split('\n')[0] : ''}`);
  process.exit(1);
});
