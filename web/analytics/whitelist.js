// The usage-data whitelist, events.json, and the check a batch from the apps has to pass before any of it is stored.
// The apps' unit tests read the same file (../web/analytics/events.json from android/ and ios/), so an event or a
// property that isn't in it never gets sent, and the server turns away any batch that has one.
//
// A batch is a JSON array of 1 to 100 events. Each event is an object with:
//   name                                                 an event in events.json: "game_open"
//   props                                                that event's properties, any of the ones events.json lists
//                                                        for it and no other: {"game": "noodle-rush", "resumed": false}
//   install_id, session_id, seq                          the common fields every event has
//   ts, app_version, build, platform, form_factor,       and the ones it may leave out (form_factor is only the kind
//   os_version, lang                                     of device: phone, tablet, desktop or watch, never its model)
// and nothing else. A field the whitelist doesn't name is refused, so nothing new is collected by mistake, and so is
// a null: an app leaves out what it doesn't have. One bad event refuses the whole batch, and nothing of it is stored.
'use strict';

const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, 'events.json');
const MAX_EVENTS = 100;
const REQUIRED = ['install_id', 'session_id', 'seq'];

// What the types in events.json mean. An id is a game, node, product or pack id as the maps and the catalog have them:
// capitals and a leading underscore included, because some nodes have them ("L1_win", "Page1", "_restart").
const ID = /^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,79}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO8601 = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-](\d{2}):(\d{2}))$/;
const CONTROL = /[\u0000-\u001f\u007f]/;
const MAX_INT = 1e9;
const MAX_STRING = 64;

// What a type's check gives back for a value that isn't of that type.
const BAD = Symbol('bad');

// A type from events.json as a check: the value to store, or BAD. A uuid is stored in lower case (iOS writes them in
// capitals) and a time in UTC. A type this file doesn't know stops the server starting (and fails the tests), rather
// than refusing every batch later.
function compile(type) {
  switch (type) {
    case 'bool': return (v) => (typeof v === 'boolean' ? v : BAD);
    case 'int': return (v) => (Number.isInteger(v) && v >= 0 && v <= MAX_INT ? v : BAD);
    case 'id': return (v) => (typeof v === 'string' && ID.test(v) ? v : BAD);
    case 'uuid': return (v) => (typeof v === 'string' && UUID.test(v) ? v.toLowerCase() : BAD);
    case 'iso8601': return (v) => (typeof v === 'string' ? utc(v) : BAD);
    // Postgres can't store a NUL, so no control characters at all (and no half of a surrogate pair either)
    case 'string':
      return (v) => (typeof v === 'string' && v.length <= MAX_STRING && !CONTROL.test(v) && v.isWellFormed() ? v : BAD);
  }
  if (typeof type === 'string' && type.startsWith('enum:')) {
    const values = type.slice('enum:'.length).split(',');
    return (v) => (values.includes(v) ? v : BAD);
  }
  throw new Error(`${path.basename(FILE)}: unknown type ${JSON.stringify(type)}`);
}

// A time from the phone, "2026-10-09T09:41:00.123Z" or with an offset ("+01:00"), as UTC to the millisecond. BAD if
// it isn't a real time (Date.parse would roll 31 February over into March) or isn't from 1970 to 2999.
function utc(text) {
  const m = ISO8601.exec(text);
  if (!m) return BAD;
  const [year, month, day, hour, minute, second] = m.slice(1, 7).map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  const real = date.getUTCMonth() === month - 1 && date.getUTCDate() === day && hour <= 23 && minute <= 59 &&
    second <= 59 && (m[7] === 'Z' || (Number(m[8]) <= 14 && Number(m[9]) <= 59));
  if (!real || year < 1970 || year > 2999) return BAD;
  return new Date(Date.parse(text)).toISOString();
}

// {"game": "id", ...} as a Map from each name to its type's check. A Map, so that "constructor" or "__proto__" is
// never mistaken for a name in the file.
function fields(spec) {
  return new Map(Object.entries(spec).map(([name, type]) => [name, compile(type)]));
}

const whitelist = JSON.parse(fs.readFileSync(FILE, 'utf8'));
const common = fields(whitelist.common);
const events = new Map(Object.entries(whitelist.events).map(([name, props]) => [name, fields(props)]));
for (const name of REQUIRED) {
  if (!common.has(name)) throw new Error(`${path.basename(FILE)}: no "${name}" in common`);
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// A name from the request, for an error message: quoted, and short.
function quote(value) {
  return JSON.stringify(String(value).slice(0, 40));
}

// One event as a row for the events table, or what's wrong with it.
function checkEvent(event) {
  if (!isObject(event)) return 'not an object';
  if (!events.has(event.name)) return event.name === undefined ? 'no name' : `unknown event ${quote(event.name)}`;

  const row = { name: event.name, props: {} };
  for (const key of common.keys()) row[key] = null;
  for (const [key, value] of Object.entries(event)) {
    if (key === 'name' || key === 'props') continue;
    const check = common.get(key);
    if (!check) return `unknown field ${quote(key)}`;
    const clean = check(value);
    if (clean === BAD) return `${quote(key)} has the wrong type`;
    row[key] = clean;
  }
  for (const key of REQUIRED) {
    if (row[key] === null) return `no ${key}`;
  }

  if (event.props !== undefined) {
    if (!isObject(event.props)) return '"props" is not an object';
    const allowed = events.get(event.name);
    for (const [key, value] of Object.entries(event.props)) {
      const check = allowed.get(key);
      if (!check) return `${event.name} has no property ${quote(key)}`;
      const clean = check(value);
      if (clean === BAD) return `${event.name}.${key} has the wrong type`;
      row.props[key] = clean;
    }
  }
  return row;
}

// The body of POST /api/events, parsed: {rows} to store, or {error}, the short reason the 400 gives.
function checkBatch(batch) {
  if (!Array.isArray(batch)) return { error: 'expected a JSON array of events' };
  if (batch.length === 0 || batch.length > MAX_EVENTS) {
    return { error: `expected 1 to ${MAX_EVENTS} events, not ${batch.length}` };
  }
  const rows = [];
  for (let i = 0; i < batch.length; i++) {
    const row = checkEvent(batch[i]);
    if (typeof row === 'string') return { error: `events[${i}]: ${row}` };
    rows.push(row);
  }
  return { rows };
}

// The body of POST /api/forget, {"install_id": "<uuid>"}, parsed: {installId}, or {error}.
function checkForget(body) {
  const keys = isObject(body) ? Object.keys(body) : [];
  if (keys.length !== 1 || keys[0] !== 'install_id') return { error: 'expected {"install_id": "<uuid>"}' };
  const installId = common.get('install_id')(body.install_id);
  return installId === BAD ? { error: '"install_id" has the wrong type' } : { installId };
}

module.exports = { checkBatch, checkForget, whitelist, commonFields: [...common.keys()], MAX_EVENTS };
