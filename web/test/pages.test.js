// The website's pages (public/*.html): the privacy policy describes exactly the details and events the whitelist
// allows (the device only as a phone, tablet, computer or watch), and every page keeps the accessibility basics: a
// language, one h1 and headings that never skip a level, landmarks, a skip link that lands, links with words that go
// somewhere, and text contrast of at least 7:1; and links the brand's icons and its social image with alt text
// (tools/make_art.py export web makes them). And nothing calls the usage data "anonymous": it's pseudonymous. Run
// with `node --test web/test/`.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { whitelist, commonFields } = require('../analytics/whitelist');

const PUBLIC = path.join(__dirname, '..', 'public');
const PAGES = fs.readdirSync(PUBLIC).filter((f) => f.endsWith('.html')).sort();
const SITE = PAGES.filter((f) => f !== '404.html'); // 404.html is only ever an answer, never linked to
const html = (file) => fs.readFileSync(path.join(PUBLIC, file), 'utf8').replace(/<!--[\s\S]*?-->/g, '');

// A page's elements, roughly, which is all these checks need.
function headings(page) {
  return [...page.matchAll(/<h([1-6])\b/g)].map((m) => Number(m[1]));
}

function ids(page) {
  return new Set([...page.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
}

function textOf(fragment) {
  return fragment.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;|&#\d+;/g, ' ').replace(/\s+/g, ' ').trim();
}

function links(page) {
  return [...page.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)].map((m) => {
    const attr = (name) => (new RegExp(`\\s${name}="([^"]*)"`).exec(m[1]) || [])[1];
    const alt = (/<img\b[^>]*\salt="([^"]*)"/.exec(m[2]) || [])[1];
    return { href: attr('href'), name: attr('aria-label') || textOf(m[2]) || alt || '', tag: m[0] };
  });
}

// The file a same-site path is served from, as server.js maps it (/ is index.html, /privacy is privacy.html).
function fileFor(urlPath) {
  const rel = urlPath === '/' ? 'index.html' : urlPath.replace(/^\//, '');
  const file = path.join(PUBLIC, rel);
  if (fs.existsSync(file) && fs.statSync(file).isFile()) return rel;
  return fs.existsSync(file + '.html') ? rel + '.html' : null;
}

// WCAG 2.x contrast of two #rrggbb colours.
function contrast(a, b) {
  const luminance = (hex) => {
    const [r, g, bl] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
      .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
  };
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

test('the privacy policy lists exactly the events in the whitelist, one line each', () => {
  const page = html('privacy.html');
  const listed = [...page.matchAll(/<li data-event="([^"]+)">/g)].map((m) => m[1]);
  assert.deepEqual([...listed].sort(), Object.keys(whitelist.events).sort());
  assert.equal(new Set(listed).size, listed.length, 'an event is listed twice');
  assert.equal([...page.matchAll(/data-event=/g)].length, listed.length, 'a data-event that is not on an <li>');
  assert.ok(ids(page).has('usage-data'));
});

test('the privacy policy describes every detail a record has, and the device only as a kind of device', () => {
  const page = html('privacy.html');
  const section = page.slice(page.indexOf('<section aria-labelledby="usage-data">'));
  const described = [...section.matchAll(/<li data-field="([^"]+)">/g)].flatMap((m) => m[1].split(' '));
  assert.deepEqual([...described].sort(), [...commonFields].sort());
  assert.equal(new Set(described).size, described.length, 'a field is described twice');
  assert.equal([...page.matchAll(/data-field=/g)].length, [...section.matchAll(/<li data-field=/g)].length,
    'a data-field that is not on an <li> in the usage data section');

  // a word on the page for each kind of device the whitelist has, and never the make or model
  const words = { phone: 'phone', tablet: 'tablet', desktop: 'computer', watch: 'watch' };
  assert.equal(whitelist.common.form_factor, `enum:${Object.keys(words).join(',')}`);
  const line = textOf(/<li data-field="form_factor">([\s\S]*?)<\/li>/.exec(page)[1]);
  for (const word of Object.values(words)) assert.match(line, new RegExp(`\\b${word}\\b`), word);
  assert.match(line, /never its make or model/);
});

test('no page calls the usage data anonymous', () => {
  for (const file of PAGES) {
    assert.doesNotMatch(fs.readFileSync(path.join(PUBLIC, file), 'utf8'), /anonym/i, file);
  }
});

test('every page has a language, one h1, and headings that never skip a level', () => {
  for (const file of PAGES) {
    const page = html(file);
    assert.match(page, /^<!doctype html>\s*<html lang="en">/i, file);
    const levels = headings(page);
    assert.equal(levels[0], 1, `${file}: the first heading is an h1`);
    assert.equal(levels.filter((l) => l === 1).length, 1, `${file}: one h1`);
    levels.forEach((level, i) => {
      if (i) assert.ok(level <= levels[i - 1] + 1, `${file}: h${levels[i - 1]} then h${level}`);
    });
  }
});

test('every page has its landmarks, a skip link first that lands on main, and the footer links', () => {
  for (const file of SITE) {
    const page = html(file);
    for (const tag of ['header', 'main', 'footer']) {
      assert.equal(page.match(new RegExp(`<${tag}\\b`, 'g')).length, 1, `${file}: one <${tag}>`);
    }
    assert.match(page, /<main id="main">/, file);
    const first = links(page)[0];
    assert.match(first.tag, /class="skip"/, `${file}: the skip link comes first`);
    assert.equal(first.href, '#main', file);
    assert.ok(/^Skip to /.test(first.name), file);
    const footer = page.slice(page.indexOf('<footer'));
    for (const href of ['/privacy', '/support', '/accessibility']) {
      assert.ok(footer.includes(`href="${href}"`), `${file}: the footer links to ${href}`);
    }
    for (const nav of page.matchAll(/<nav\b([^>]*)>/g)) {
      assert.match(nav[1], /aria-label="[^"]+"/, `${file}: a nav's name`);
    }
  }
});

test('every link has words that say where it goes, and every same-site link lands', () => {
  const vague = /^(click here|here|more|read more|link|this)$/i;
  for (const file of PAGES) {
    const page = html(file);
    for (const link of links(page)) {
      assert.ok(link.href, `${file}: ${link.tag}`);
      assert.ok(link.name && !vague.test(link.name), `${file}: a link without a name of its own: ${link.tag}`);
      if (/^(https?:|mailto:)/.test(link.href)) continue;
      const [urlPath, fragment] = link.href.split('#');
      const target = urlPath ? fileFor(urlPath) : file;
      assert.ok(target, `${file}: ${link.href} goes nowhere`);
      if (fragment) assert.ok(ids(html(target)).has(fragment), `${file}: ${link.href}: no id="${fragment}" there`);
    }
    for (const img of page.matchAll(/<img\b[^>]*>/g)) assert.match(img[0], /\salt="/, `${file}: ${img[0]}`);
  }
});

test('text has a contrast of at least 7:1 on the page background', () => {
  for (const file of PAGES) {
    const page = html(file);
    const token = (name) => (new RegExp(`--${name}:\\s*(#[0-9a-f]{6})`, 'i').exec(page) || [])[1];
    const bg = token('bg') || '#0b1430';
    if (token('bg')) {
      for (const name of ['ink', 'muted', 'faint', 'accent']) {
        assert.ok(contrast(token(name), bg) >= 7, `${file}: --${name} ${contrast(token(name), bg).toFixed(2)}:1`);
      }
      assert.ok(contrast(token('accent-ink'), token('accent')) >= 7, `${file}: --accent-ink on --accent`);
    }
    for (const m of page.matchAll(/[^-]color:\s*(#[0-9a-f]{6}|#[0-9a-f]{3})\b/gi)) {
      const hex = m[1].length === 4 ? '#' + [...m[1].slice(1)].map((c) => c + c).join('') : m[1];
      assert.ok(contrast(hex, bg) >= 7, `${file}: color ${m[1]} is ${contrast(hex, bg).toFixed(2)}:1`);
    }
  }
});

test('every page links the icons and the web manifest, and the social image with its alt text', () => {
  const exists = (urlPath) => fs.existsSync(path.join(PUBLIC, urlPath));
  const manifest = JSON.parse(fs.readFileSync(path.join(PUBLIC, 'manifest.webmanifest'), 'utf8'));
  for (const icon of manifest.icons) assert.ok(exists(icon.src), `manifest.webmanifest: ${icon.src}`);
  assert.ok(manifest.icons.some((icon) => icon.purpose === 'maskable'), 'manifest.webmanifest: a maskable icon');

  const alts = new Set();
  for (const file of PAGES) {
    const page = html(file);
    const head = page.slice(0, page.indexOf('</head>'));
    for (const href of ['/favicon.ico', '/apple-touch-icon.png', '/manifest.webmanifest']) {
      assert.ok(head.includes(`href="${href}"`), `${file}: no link to ${href}`);
      assert.ok(exists(href), `${href} isn't there`);
    }
    // the old headphones icon: browsers would pick an SVG over the new icon
    assert.doesNotMatch(head, /favicon\.svg/, file);
    if (file === '404.html') continue; // never shared, so no social image
    const meta = (key) => (new RegExp(`<meta (?:property|name)="${key}" content="([^"]*)">`).exec(head) || [])[1];
    assert.equal(meta('og:image'), 'https://epicaudiogames.com/og-v2.png', file);
    assert.ok(exists('/og-v2.png'));
    assert.ok(meta('og:image:alt'), `${file}: og:image:alt`);
    assert.equal(meta('twitter:image:alt'), meta('og:image:alt'), `${file}: twitter:image:alt`);
    alts.add(meta('og:image:alt'));
  }
  assert.equal(alts.size, 1, 'one image, one alt text');
});

test('the sitemap lists every page', () => {
  const sitemap = fs.readFileSync(path.join(PUBLIC, 'sitemap.xml'), 'utf8');
  const listed = [...sitemap.matchAll(/<loc>https:\/\/epicaudiogames\.com(\/[^<]*)<\/loc>/g)].map((m) => m[1]);
  const pages = SITE.map((f) => (f === 'index.html' ? '/' : '/' + f.replace(/\.html$/, '')));
  assert.deepEqual(listed.sort(), pages.sort());
});

test('support: no mic that opens by itself, buying in the Shop tab, TalkBack, and the statement linked', () => {
  const page = html('support.html');
  assert.doesNotMatch(page, /\b(mic|microphone) opens by itself/i);
  assert.match(page, /Open the <strong>Shop<\/strong> tab/);
  const access = page.slice(page.indexOf('<h2 id="access">'), page.indexOf('<h2 id="privacy">'));
  assert.match(access, /VoiceOver/);
  assert.match(access, /TalkBack's two-finger double tap[\s\S]*still testing/);
  assert.match(access, /href="\/accessibility"/);
  assert.match(page, /<a href="#privacy">Privacy and usage data<\/a>/);
});

test('privacy: an effective date, and no "no tracking" or "no analytics" left from before usage data', () => {
  const page = html('privacy.html');
  assert.match(page, /<span class="eyebrow">Effective \d{1,2} [A-Z][a-z]+ 20\d\d<\/span>/);
  assert.doesNotMatch(page, /no tracking|no analytics or tracking|contains no analytics/i);
  assert.match(page, /legitimate interests/);
  assert.match(page, /13 months/);
});

test('privacy: what the apps do with usage data, and what passes between a phone and a watch', () => {
  const text = textOf(html('privacy.html'));
  // both apps: nothing goes before the welcome is over; turning off forgets the ID and the unsent records only, so
  // what was sent before is deleted with Delete my usage data; unsent records wait 7 days at most (EventQueue)
  assert.match(text, /sends nothing until you've finished or skipped the welcome/);
  assert.match(text, /doesn't delete what was sent before/);
  assert.match(text, /up to 7 days/);
  assert.match(text, /United States \(Virginia\)/);
  const watches = textOf(/<section aria-labelledby="watches">([\s\S]*?)<\/section>/.exec(html('privacy.html'))[1]);
  assert.match(watches, /send nothing to us/);
  assert.match(watches, /Apple Watch/);
  assert.match(watches, /Wear OS/);
});

test('accessibility and support: tablets, keyboards and watches, as the apps have them', () => {
  for (const file of ['accessibility.html', 'support.html']) {
    const text = textOf(html(file));
    // the shortcuts the apps' own help gives (tools/app_text.toml, "Typing and choosing answers")
    for (const words of ['Space', 'Escape pauses the game', 'Control with 1 to 4', 'Command with 1 to 4']) {
      assert.ok(text.includes(words), `${file}: ${words}`);
    }
    assert.match(text, /iPad/, file);
    assert.match(text, /Chromebooks/, file);
    assert.match(text, /Apple Watch/, file);
    assert.match(text, /Wear OS/, file);
    assert.match(text, /buzzes when the microphone opens/, file);
  }
  // the tabs are only along the bottom on a phone
  assert.doesNotMatch(textOf(html('support.html')), /tab at the bottom of the screen/);
});
