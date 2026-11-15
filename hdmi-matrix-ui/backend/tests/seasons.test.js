'use strict';
// Run with: node --test hdmi-matrix-ui/backend/tests/seasons.test.js
// (test_seasons.py wraps this so `pytest` and CI pick it up.)
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const S = require(path.join(__dirname, '..', '..', 'frontend', 'seasons.js'));

const d = (y, m, day) => new Date(y, m - 1, day); // 1-based month, readable in assertions
const themeId = (date, settings = {}, region = 'us') => {
  const t = S.resolve(date, settings, region);
  return t ? t.id : null;
};

// WCAG: 4.5:1 for text on the accent, 3:1 for the accent as a UI component on the page background.
const TEXT = { dark: '#f7f9fb', light: '#0e1217' }; // --text in styles.css
function assertReadable(theme, label) {
  for (const scheme of ['dark', 'light']) {
    const vars = S.cssVars(theme, scheme);
    const where = `${label} (${scheme})`;
    assert.ok(S.contrast(vars['--accent'], vars['--accent-text']) >= 4.5, `${where}: accent text < 4.5:1`);
    assert.ok(S.contrast(vars['--accent'], vars['--bg']) >= 3, `${where}: accent vs background < 3:1`);
    assert.ok(S.contrast(TEXT[scheme], vars['--bg']) >= 7, `${where}: body text vs background < 7:1`);
  }
}

// ---------- Halloween (pilot) ----------

test('halloween covers all of October and nothing else', () => {
  assert.equal(themeId(d(2026, 9, 30)), null);
  assert.equal(themeId(d(2026, 10, 1)), 'halloween');
  assert.equal(themeId(d(2026, 10, 15)), 'halloween');
  assert.equal(themeId(d(2026, 10, 31)), 'halloween');
  assert.equal(themeId(d(2026, 11, 1)), null);
});

test('mode "off" disables every theme', () => {
  assert.equal(themeId(d(2026, 10, 31), { mode: 'off' }), null);
});

test('preview mode shows a theme outside its window', () => {
  assert.equal(themeId(d(2026, 7, 4), { mode: 'force:halloween' }), 'halloween');
  assert.equal(themeId(d(2026, 7, 4), { mode: 'force:nonsense' }), null);
});

test('halloween palette is readable in dark and light', () => {
  assertReadable(S.resolve(d(2026, 10, 31), {}, 'us'), 'halloween');
});

test('themes never override status, text or border tokens', () => {
  const forbidden = ['--on', '--on-text', '--danger', '--danger-text', '--text', '--text-dim', '--border', '--surface'];
  for (const name of S.CSS_VAR_NAMES) assert.ok(!forbidden.includes(name), `${name} must stay with the base theme`);
});

test('locale to region', () => {
  assert.equal(S.regionFromLocale('en-US'), 'us');
  assert.equal(S.regionFromLocale('en-CA'), 'ca');
  assert.equal(S.regionFromLocale('fr-CA'), 'ca');
  assert.equal(S.regionFromLocale('en-GB'), 'other');
  assert.equal(S.regionFromLocale('en'), 'us');
});

// ---------- date rules ----------

const iso = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

test('Thanksgiving dates (US: 4th Thursday of Nov, CA: 2nd Monday of Oct)', () => {
  const us = [[2026, '2026-11-26'], [2027, '2027-11-25'], [2028, '2028-11-23'], [2030, '2030-11-28']];
  for (const [year, want] of us) assert.equal(iso(S.HOLIDAYS['thanksgiving-us'].span(year).first), want);
  const ca = [[2026, '2026-10-12'], [2027, '2027-10-11'], [2028, '2028-10-09'], [2030, '2030-10-14']];
  for (const [year, want] of ca) assert.equal(iso(S.HOLIDAYS['thanksgiving-ca'].span(year).first), want);
});

test('Hanukkah first candle (evening before 25 Kislev) matches the published calendar', () => {
  const want = {
    2024: '2024-12-25', 2025: '2025-12-14', 2026: '2026-12-04', 2027: '2027-12-24',
    2028: '2028-12-12', 2029: '2029-12-01', 2030: '2030-12-20',
  };
  for (const [year, date] of Object.entries(want)) assert.equal(iso(S.hanukkahEve(Number(year))), date, String(year));
});

// ---------- Thanksgiving ----------

test('US Thanksgiving shows for the fortnight up to and including the day', () => {
  assert.equal(themeId(d(2026, 11, 11), {}, 'us'), null);
  assert.equal(themeId(d(2026, 11, 12), {}, 'us'), 'thanksgiving-us');
  assert.equal(themeId(d(2026, 11, 26), {}, 'us'), 'thanksgiving-us');
});

test('Thanksgiving follows the region: CA in Oct, nothing elsewhere', () => {
  assert.equal(themeId(d(2026, 10, 12), {}, 'ca'), 'thanksgiving-ca');
  assert.equal(themeId(d(2026, 11, 20), {}, 'ca') === 'thanksgiving-us', false);
  assert.equal(themeId(d(2026, 11, 15), {}, 'other'), null);
  assert.equal(themeId(d(2026, 11, 15), { region: 'us' }, 'other'), 'thanksgiving-us', 'explicit region overrides locale');
});

test('Canadian Thanksgiving hands over to Halloween after the holiday; US keeps Halloween all month', () => {
  assert.equal(themeId(d(2026, 10, 5), {}, 'ca'), 'thanksgiving-ca');
  assert.equal(themeId(d(2026, 10, 13), {}, 'ca'), 'halloween');
  assert.equal(themeId(d(2026, 10, 5), {}, 'us'), 'halloween');
});

test('Thanksgiving palette is readable', () => {
  assertReadable(S.resolve(d(2026, 11, 20), {}, 'us'), 'thanksgiving');
});

// ---------- winter ----------

test('winter blend runs from the Hanukkah lead-in to Jan 1, after Thanksgiving in the US', () => {
  assert.equal(themeId(d(2026, 11, 20)), 'thanksgiving-us', 'Thanksgiving (Nov 26) is next up, so it wins the overlap');
  assert.equal(themeId(d(2026, 11, 27)), 'winter');
  assert.equal(themeId(d(2026, 12, 31)), 'winter');
  assert.equal(themeId(d(2027, 1, 1)), 'winter');
  assert.equal(themeId(d(2027, 1, 2)), null);
});

test('winter blend reaches each holiday\'s own palette on its middle day', () => {
  // Christmas is a single day, so on Dec 25 the blend is exactly the Christmas palette.
  const t = S.resolve(d(2026, 12, 25), {}, 'us');
  assert.equal(t.id, 'winter');
  assert.equal(t.palettes.dark.accent, S.PALETTES.christmas.dark.accent);
  // New Year's Day is the last stop.
  assert.equal(S.resolve(d(2027, 1, 1), {}, 'us').palettes.light.accent, S.PALETTES.newyear.light.accent);
});

test('blend order follows the calendar when Hanukkah moves (2027: Christmas, then Hanukkah)', () => {
  const accent = (date) => S.resolve(date, {}, 'us').palettes.dark.accent;
  assert.equal(accent(d(2027, 12, 20)), S.PALETTES.christmas.dark.accent, 'holds the first stop until it arrives');
  assert.equal(accent(d(2027, 12, 25)), S.PALETTES.christmas.dark.accent);
  assert.notEqual(accent(d(2027, 12, 26)), S.PALETTES.christmas.dark.accent, 'glides toward Hanukkah');
  assert.equal(accent(d(2027, 12, 28)), S.PALETTES.hanukkah.dark.accent, 'Hanukkah 2027 midpoint');
  assert.equal(S.resolve(d(2028, 1, 1), {}, 'us').id, 'winter', 'Hanukkah 2027 runs through Jan 1 2028');
});

test('users can leave holidays out of the blend', () => {
  const noXmas = { winterHolidays: ['hanukkah', 'kwanzaa', 'newyear'] };
  const t = S.resolve(d(2026, 12, 25), noXmas, 'us');
  assert.equal(t.id, 'winter');
  assert.notEqual(t.palettes.dark.accent, S.PALETTES.christmas.dark.accent);
  assert.equal(themeId(d(2026, 12, 25), { winterHolidays: [] }), null, 'nothing included, nothing shown');
});

test('individual mode shows one holiday at a time, in order', () => {
  const solo = { winter: 'individual' };
  assert.equal(themeId(d(2026, 11, 27), solo), 'hanukkah');
  assert.equal(themeId(d(2026, 12, 11), solo), 'hanukkah', 'still inside Hanukkah (ends Dec 12)');
  assert.equal(themeId(d(2026, 12, 13), solo), 'christmas');
  assert.equal(themeId(d(2026, 12, 25), solo), 'christmas');
  assert.equal(themeId(d(2026, 12, 28), solo), 'kwanzaa');
  assert.equal(themeId(d(2026, 12, 31), solo), 'kwanzaa');
  assert.equal(themeId(d(2027, 1, 1), solo), 'newyear', 'the most specific holiday wins on Jan 1');
  assert.equal(themeId(d(2027, 12, 25), solo), 'christmas', 'Christmas Day beats an overlapping Hanukkah');
});

test('winter preview shows the blend', () => {
  assert.equal(themeId(d(2026, 7, 4), { mode: 'force:winter' }), 'winter');
});

// ---------- accessibility across every day ----------

test('every individual palette is readable', () => {
  for (const id of Object.keys(S.HOLIDAYS)) assertReadable(S.resolve(d(2026, 7, 4), { mode: `force:${id}` }), id);
});

test('the blended palette is readable on every day of every winter, 2024-2032', () => {
  for (let year = 2024; year <= 2032; year++) {
    for (let date = d(year, 11, 1); date <= d(year + 1, 1, 1); date = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1)) {
      const t = S.resolve(date, {}, 'us');
      if (t && t.id === 'winter') assertReadable(t, `winter ${iso(date)}`);
    }
  }
});
