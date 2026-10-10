// The usage-data whitelist (analytics/events.json) and the check every batch from the apps passes
// (analytics/whitelist.js). Run with `node --test web/test/`.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { checkBatch, checkForget, whitelist, commonFields, MAX_EVENTS } = require('../analytics/whitelist');
const { COLUMNS } = require('../analytics/store');

const SMOKE = JSON.parse(fs.readFileSync(path.join(__dirname, 'smoke-events.json'), 'utf8'));
const INSTALL = '00000000-0000-4000-8000-000000000001';
const SESSION = '00000000-0000-4000-8000-000000000002';
const IOS_UUID = 'E621E1F8-C36C-495A-93FC-0C247A3E6E5F'; // as iOS's UUID().uuidString writes one

// A good event, with `changes` made to it (a change to undefined leaves that field out).
function event(changes) {
  const e = Object.assign({ name: 'game_open', props: { game: 'noodle-rush', resumed: false }, install_id: INSTALL,
    session_id: SESSION, seq: 0, ts: '2026-10-09T09:41:00Z' }, changes);
  for (const key of Object.keys(e)) if (e[key] === undefined) delete e[key];
  return e;
}

function refused(e) {
  const checked = checkBatch([e]);
  assert.ok(checked.error, `should be refused: ${JSON.stringify(e)}`);
  return checked.error;
}

function accepted(e) {
  const checked = checkBatch([e]);
  assert.equal(checked.error, undefined, `should pass: ${JSON.stringify(e)}`);
  return checked.rows[0];
}

test('the whitelist parses, in the format the apps read', () => {
  const file = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'analytics', 'events.json'), 'utf8'));
  assert.deepEqual(file, whitelist);
  assert.equal(whitelist.format, 1);
  assert.ok(Object.keys(whitelist.events).length > 0);
  for (const [name, props] of Object.entries(whitelist.events)) {
    assert.match(name, /^[a-z][a-z_]*$/, name);
    for (const type of Object.values(props)) assert.equal(typeof type, 'string', name);
  }
  assert.ok(Array.isArray(whitelist.never) && whitelist.never.length > 0);
  // (whitelist.js has already compiled every type: one it didn't know would have thrown on require)
});

test('nothing in the whitelist can carry an accessibility setting, the player\'s words or who they are', () => {
  const names = [...commonFields, ...Object.keys(whitelist.events)];
  for (const props of Object.values(whitelist.events)) names.push(...Object.keys(props));
  const forbidden = new RegExp([
    'reader', 'talkback', 'voiceover', 'access', 'theme', 'contrast', 'text_?size', 'scale', 'font', 'motion', 'speed',
    'volume', 'music', 'answer_?time', 'policy', 'topic', 'said', 'text', 'transcript', 'audio', 'device', 'model',
    'advert', 'location', '^ip$', '_ip$', 'email', 'phone', 'name',
  ].join('|'));
  for (const name of names) assert.doesNotMatch(name, forbidden, name);
});

test('the events table has a column for every common field, and nothing else from the request', () => {
  assert.deepEqual([...COLUMNS].sort(), [...commonFields, 'name', 'props'].sort());
});

test('the smoke batch has every event in the whitelist, and passes', () => {
  assert.deepEqual(new Set(SMOKE.map((e) => e.name)), new Set(Object.keys(whitelist.events)));
  for (const e of SMOKE) {
    assert.equal(e.install_id, INSTALL);
    assert.deepEqual(Object.keys(e.props).sort(), Object.keys(whitelist.events[e.name]).sort(), e.name);
  }
  const checked = checkBatch(SMOKE);
  assert.equal(checked.error, undefined);
  assert.equal(checked.rows.length, SMOKE.length);
});

test('a good event becomes a row: uuids in lower case, the time in UTC, what was left out null', () => {
  const row = accepted(event({ install_id: IOS_UUID, ts: '2026-10-09T10:41:00.5+01:00', seq: 7 }));
  assert.deepEqual(row, {
    name: 'game_open', props: { game: 'noodle-rush', resumed: false }, install_id: IOS_UUID.toLowerCase(),
    session_id: SESSION, seq: 7, ts: '2026-10-09T09:41:00.500Z', app_version: null, build: null, platform: null,
    form_factor: null, os_version: null, lang: null,
  });
  // every common field, as the apps send them
  const full = accepted(event({ ts: '2026-10-09T09:41:00.123456789Z', app_version: '1.0', build: '3', platform: 'ios',
    form_factor: 'tablet', os_version: '18.1', lang: 'en-GB' }));
  assert.equal(full.ts, '2026-10-09T09:41:00.123Z');
  assert.equal(full.platform, 'ios');
  assert.equal(full.form_factor, 'tablet');
});

test('form_factor is only the kind of device: phone, tablet, desktop or watch, never a make or model', () => {
  assert.equal(whitelist.common.form_factor, 'enum:phone,tablet,desktop,watch');
  for (const kind of ['phone', 'tablet', 'desktop', 'watch']) {
    assert.equal(accepted(event({ form_factor: kind })).form_factor, kind);
  }
  // models as Android (Build.MODEL) and iOS (the machine name) give them, and words near enough to fool a looser check
  for (const value of ['Pixel 9', 'SM-S921B', 'iPad13,8', 'iPhone17,1', 'Mac', 'iPad', 'Phone', 'TABLET', ' phone',
    'phone ', 'foldable', 'chromebook', 'tv', 'car', 'vision', '', 'phone,tablet', null, 0, true, ['phone']]) {
    assert.match(refused(event({ form_factor: value })), /"form_factor" has the wrong type/, JSON.stringify(value));
  }
  // an app from before form_factor leaves it out, like the other fields after the first three
  assert.equal(accepted(event({})).form_factor, null);
});

test('ids as the maps and the catalog have them pass', () => {
  for (const node of ['L1_win', 'L2_intro', 'Page1', '_restart', 'ac-diffGame', 'fr2-0', 'a', 'x'.repeat(80)]) {
    accepted(event({ name: 'game_end', props: { game: 'alien-customs', kind: 'chapter', node } }));
  }
  accepted(event({ name: 'purchase_start', props: { product: 'com.epicaudiogames.app.frootopia_stories' } }));
});

test('an unknown event, field or property is refused', () => {
  assert.match(refused(event({ name: 'screen_reader_on' })), /unknown event "screen_reader_on"/);
  assert.match(refused(event({ name: undefined })), /no name/);
  for (const name of ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'GAME_OPEN', 42, null]) {
    assert.match(refused(event({ name })), /unknown event/);
  }
  assert.match(refused(event({ ip: '203.0.113.9' })), /unknown field "ip"/);
  for (const field of ['device_model', 'theme', 'screen_reader', 'said', 'event', 'id', 'received_at']) {
    assert.match(refused(event({ [field]: 'x' })), /unknown field/, field);
  }
  assert.match(refused(event({ name: 'help_viewed', props: { source: 'tab', topic: 'voice' } })),
    /help_viewed has no property "topic"/);
  assert.match(refused(event({ props: JSON.parse('{"game": "noodle-rush", "__proto__": {"x": 1}}') })),
    /no property "__proto__"/);
  assert.match(refused(event({ props: { game: 'noodle-rush', constructor: 'x' } })), /no property "constructor"/);
});

test('a value of the wrong type is refused', () => {
  const wrong = [
    ['seq', '1'], ['seq', -1], ['seq', 1.5], ['seq', 1e9 + 1], ['seq', null], ['seq', true],
    ['install_id', 'not-a-uuid'], ['install_id', 123], ['install_id', '00000000-0000-4000-8000-00000000000g'],
    ['session_id', `${SESSION} `],
    ['ts', '2026-02-31T00:00:00Z'], ['ts', '2026-13-01T00:00:00Z'], ['ts', '2026-10-09 09:41:00'],
    ['ts', '2026-10-09T09:41:00'], ['ts', '2026-10-09T24:00:00Z'], ['ts', '2026-10-09T23:59:60Z'],
    ['ts', '1969-12-31T23:59:59Z'], ['ts', '2026-10-09T09:41:00+15:00'], ['ts', 1791538860000], ['ts', null],
    ['platform', 'windows'], ['platform', 'iOS'], ['app_version', 'x'.repeat(65)], ['lang', 'en\u0000'],
    ['lang', 'en\n'], ['build', '\ud800'], ['os_version', 15],
  ];
  for (const [field, value] of wrong) {
    assert.match(refused(event({ [field]: value })), new RegExp(`"${field}" has the wrong type`), `${field}: ${value}`);
  }
  const wrongProps = [
    { game: 'Noodle Rush' }, { game: '' }, { game: 'x'.repeat(81) }, { game: '-noodle' }, { game: 'noodle/rush' },
    { game: null }, { resumed: 'false' }, { resumed: 0 },
  ];
  for (const props of wrongProps) assert.match(refused(event({ props })), /game_open\.\w+ has the wrong type/);
  assert.match(refused(event({ name: 'game_end', props: { kind: 'won' } })), /game_end\.kind/);
  assert.match(refused(event({ name: 'app_background', props: { seconds: -5 } })), /app_background\.seconds/);
});

test('install_id, session_id and seq must be there; the rest may be left out', () => {
  for (const field of ['install_id', 'session_id', 'seq']) {
    assert.match(refused(event({ [field]: undefined })), new RegExp(`no ${field}`));
  }
  accepted(event({ ts: undefined }));
  accepted({ name: 'game_restart', install_id: INSTALL, session_id: SESSION, seq: 3 });
});

test('props is an object, or left out', () => {
  for (const props of [[], 'x', null, 1]) assert.match(refused(event({ props })), /"props" is not an object/);
  assert.deepEqual(accepted(event({ name: 'game_restart', props: undefined })).props, {});
  assert.deepEqual(accepted(event({ name: 'game_restart', props: {} })).props, {});
  // any of an event's properties may be left out
  assert.deepEqual(accepted(event({ props: { game: 'noodle-rush' } })).props, { game: 'noodle-rush' });
});

test(`a batch is an array of 1 to ${MAX_EVENTS} events, and one bad event refuses all of it`, () => {
  assert.match(checkBatch({}).error, /expected a JSON array/);
  assert.match(checkBatch(null).error, /expected a JSON array/);
  assert.match(checkBatch([]).error, /expected 1 to 100 events, not 0/);
  const many = Array.from({ length: MAX_EVENTS + 1 }, (_, seq) => event({ seq }));
  assert.match(checkBatch(many).error, /not 101/);
  assert.equal(checkBatch(many.slice(1)).rows.length, MAX_EVENTS);
  assert.match(checkBatch([...SMOKE, event({ name: 'nope' })]).error, /^events\[19\]: unknown event "nope"$/);
  assert.match(checkBatch([event({}), 'x']).error, /^events\[1\]: not an object$/);
});

test('a forget request is just an install id', () => {
  assert.deepEqual(checkForget({ install_id: INSTALL }), { installId: INSTALL });
  assert.deepEqual(checkForget({ install_id: IOS_UUID }), { installId: IOS_UUID.toLowerCase() });
  for (const body of [{}, [], null, INSTALL, { install_id: 'nope' }, { install_id: INSTALL, seq: 1 },
    { installId: INSTALL }]) {
    assert.ok(checkForget(body).error, JSON.stringify(body));
  }
});
