'use strict';

// Runs the shared cases in docs/holidays.json against the web app's
// holiday logic -- the same file MatrixKit's HolidayFixtureTests.swift
// runs -- and checks the palettes against the stylesheet's contrast
// baseline. No dependencies: `node --test hdmi-matrix-ui/frontend-tests`.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repo = path.resolve(__dirname, '..', '..');
const frontend = path.join(repo, 'hdmi-matrix-ui', 'frontend');
const SOURCE = path.join(repo, 'docs', 'holidays.json');
const COPIES = [
  path.join(frontend, 'holidays.json'),
  path.join(repo, 'ios-app', 'MatrixKit', 'Sources', 'MatrixKit', 'Resources', 'holidays.json'),
];

const themes = require(path.join(frontend, 'holidays.js'));
const catalog = JSON.parse(fs.readFileSync(SOURCE, 'utf8'));
const styles = fs.readFileSync(path.join(frontend, 'styles.css'), 'utf8');

const HEX = /^#[0-9a-f]{6}$/;

test('the shipped copies match docs/holidays.json', () => {
  const source = fs.readFileSync(SOURCE, 'utf8');
  for (const copy of COPIES) {
    assert.equal(fs.readFileSync(copy, 'utf8'), source, `${path.relative(repo, copy)} is out of date`);
  }
});

test('every holiday is well formed', () => {
  assert.ok(catalog.holidays.length > 0);
  const ids = catalog.holidays.map((h) => h.id);
  assert.equal(new Set(ids).size, ids.length, 'holiday ids are unique');

  for (const holiday of catalog.holidays) {
    assert.match(holiday.id, /^[a-z0-9-]+$/);
    assert.ok(holiday.name, holiday.id);
    assert.ok(['fixed', 'nth-weekday', 'offset'].includes(holiday.rule.type), holiday.id);
    if (holiday.rule.type === 'offset') assert.ok(ids.includes(holiday.rule.from), holiday.id);
    assert.ok(Number.isInteger(holiday.window.before) && holiday.window.before >= 0, holiday.id);
    assert.ok(Number.isInteger(holiday.window.after) && holiday.window.after >= 0, holiday.id);
    for (const region of holiday.regions || []) assert.ok(catalog.regions.includes(region), holiday.id);

    // Themes override palette tokens only: exactly the declared set, per scheme.
    for (const scheme of ['dark', 'light']) {
      assert.deepEqual(Object.keys(holiday.palette[scheme]).sort(), [...catalog.tokens].sort(), holiday.id);
      for (const value of Object.values(holiday.palette[scheme])) assert.match(value, HEX, holiday.id);
    }
  }
});

test('active-holiday cases', () => {
  assert.ok(catalog.cases.active.length > 0);
  for (const c of catalog.cases.active) {
    const found = themes.activeHoliday(catalog, themes.parseDate(c.date), c.region);
    assert.equal(found ? found.id : null, c.expect, `${c.date} ${c.region}`);
  }
});

test('upcoming-holiday cases', () => {
  assert.ok(catalog.cases.upcoming.length > 0);
  for (const c of catalog.cases.upcoming) {
    const found = themes.upcomingHoliday(catalog, themes.parseDate(c.date), c.region);
    assert.equal(found ? found.id : null, c.expect, `${c.date} ${c.region}`);
  }
});

test('locale-region cases', () => {
  for (const c of catalog.cases.locale_regions) {
    assert.equal(themes.regionFromLocale(c.locale), c.expect, c.locale);
  }
  assert.equal(themes.regionFromLocale('en'), '');
  assert.equal(themes.regionFromLocale(undefined), '');
});

test('a rule this version does not know is never active', () => {
  const odd = { holidays: [{ id: 'x', rule: { type: 'lunar' }, window: { before: 0, after: 0 } }] };
  assert.equal(themes.activeHoliday(odd, { year: 2026, month: 1, day: 1 }, 'US'), null);
  const loop = { holidays: [{ id: 'x', rule: { type: 'offset', from: 'x', days: 1 }, window: {} }] };
  assert.equal(themes.activeHoliday(loop, { year: 2026, month: 1, day: 1 }, 'US'), null);
});

// ---------- palette vs. the stylesheet ----------

function baseTokens(selector) {
  const start = styles.indexOf(`${selector} {`);
  assert.notEqual(start, -1, selector);
  const block = styles.slice(start, styles.indexOf('}', start));
  const tokens = {};
  for (const [, name, value] of block.matchAll(/(--[a-z0-9-]+):\s*([^;]+);/g)) tokens[name] = value.trim();
  return tokens;
}

const BASE = { dark: baseTokens(':root'), light: baseTokens(':root[data-theme="light"]') };

function luminance(hex) {
  const n = parseInt(hex.slice(1), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
    const s = v / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

// Foreground/background pairs the palette tokens take part in. Surfaces
// are the opaque ones, which is what prefers-contrast: more falls back to.
const PAIRS = [
  ['--accent-text', '--accent'],
  ['--accent', '--surface'],
  ['--accent', '--surface-raised'],
  ['--accent', '--bg'],
  ['--focus-ring', '--bg'],
  ['--text', '--bg'],
  ['--text-dim', '--bg'],
];

test('themes only set palette tokens, never status colors', () => {
  const allowed = new Set([
    '--bg', '--accent', '--accent-text', '--focus-ring',
    '--accent-surface', '--accent-shadow', '--ambient-a', '--ambient-b',
  ]);
  for (const holiday of catalog.holidays) {
    for (const scheme of ['dark', 'light']) {
      for (const name of Object.keys(themes.cssVariables(holiday.palette[scheme], scheme))) {
        assert.ok(allowed.has(name), `${holiday.id} sets ${name}`);
        assert.ok(name in BASE[scheme], `${name} is not a stylesheet token`);
      }
    }
  }
});

test('themes keep the contrast baseline', () => {
  for (const holiday of catalog.holidays) {
    for (const scheme of ['dark', 'light']) {
      const base = BASE[scheme];
      const themed = { ...base, ...themes.cssVariables(holiday.palette[scheme], scheme) };
      for (const [fg, bg] of PAIRS) {
        // As good as the default theme, or AAA (7:1) where the default exceeds it.
        const required = Math.min(contrast(base[fg], base[bg]), 7);
        const actual = contrast(themed[fg], themed[bg]);
        assert.ok(
          actual >= required,
          `${holiday.id} ${scheme}: ${fg} on ${bg} is ${actual.toFixed(2)}:1, needs ${required.toFixed(2)}:1`
        );
      }
    }
  }
});

test('themeCss covers both schemes and rejects a broken palette', () => {
  const holiday = catalog.holidays[0];
  const css = themes.themeCss(catalog, holiday);
  assert.match(css, /^:root \{ /m);
  assert.match(css, /:root\[data-theme="light"\] \{ /);
  assert.match(css, /prefers-color-scheme: light.*:root:not\(\[data-theme="dark"\]\)/);
  assert.ok(css.includes(`--accent: ${holiday.palette.dark.accent};`));
  assert.ok(css.includes(`--accent: ${holiday.palette.light.accent};`));
  assert.ok(!/--(on|danger)\b/.test(css));

  const broken = { ...holiday, palette: { dark: { accent: 'red; } body { display: none' }, light: {} } };
  assert.equal(themes.themeCss(catalog, broken), '');
  assert.equal(themes.themeCss(catalog, null), '');
});
