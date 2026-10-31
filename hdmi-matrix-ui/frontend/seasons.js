'use strict';
/* Seasonal themes: date rules, palettes and blending.
 *
 * Pure logic, no DOM. app.js applies the result as inline CSS custom properties on <html>;
 * backend/tests/seasons.test.js runs the same file under Node.
 *
 * Rules (see issue #88):
 *  - Halloween: the whole month of October.
 *  - Every other holiday: a 14-day lead-in before its first day, through its last day.
 *  - When windows overlap, the holiday you are inside wins; otherwise the next one coming up.
 *  - Winter holidays can be shown "blended": one continuous season whose palette glides from
 *    one holiday to the next. Users choose which winter holidays take part.
 *  - Themes only touch accent/background/glow tokens. Status colors (--on, --danger), text and
 *    borders are never overridden, so the contrast baseline of the base theme still holds.
 */
(function (root) {
  const DAY_MS = 86400000;
  const LEAD_DAYS = 14;

  // ---------- date helpers (all local-time, midnight-normalised) ----------

  const day = (y, m, d) => new Date(y, m, d);
  const addDays = (date, n) => new Date(date.getFullYear(), date.getMonth(), date.getDate() + n);
  const startOfDay = (date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const daysBetween = (a, b) => Math.round((startOfDay(b) - startOfDay(a)) / DAY_MS);

  // n-th given weekday (0 = Sunday) of a month (0 = January)
  function nthWeekday(year, month, weekday, n) {
    const offset = (weekday - day(year, month, 1).getDay() + 7) % 7;
    return day(year, month, 1 + offset + 7 * (n - 1));
  }

  // Hanukkah follows the Hebrew calendar. Intl knows it, so no dependency is needed.
  const hebrewFormat = new Intl.DateTimeFormat('en-u-ca-hebrew', { day: 'numeric', month: 'long' });
  function hebrewDate(date) {
    const parts = hebrewFormat.formatToParts(date);
    return {
      day: Number(parts.find((p) => p.type === 'day').value),
      month: parts.find((p) => p.type === 'month').value,
    };
  }

  // First candle is lit at sundown the evening before 25 Kislev. 25 Kislev lands between
  // Nov 29 and Dec 27, so the scan range is generous.
  function hanukkahEve(year) {
    for (let d = day(year, 10, 20); d < day(year + 1, 0, 6); d = addDays(d, 1)) {
      const h = hebrewDate(d);
      if (h.month === 'Kislev' && h.day === 25) return addDays(d, -1);
    }
    throw new Error('Hanukkah not found for ' + year);
  }

  // ---------- holidays ----------
  // span(y): the holiday itself. window(y): when the theme shows (defaults to LEAD_DAYS before
  // the first day through the last day). regions: null = everywhere. "y" is the season year, so
  // New Year's for y is Jan 1 of y + 1 and belongs to the winter that starts in y.

  const HOLIDAYS = {
    halloween: {
      id: 'halloween',
      name: 'Halloween',
      glyph: '\u{1F383}',
      regions: null,
      span: (y) => ({ first: day(y, 9, 31), last: day(y, 9, 31) }),
      window: (y) => ({ start: day(y, 9, 1), end: day(y, 9, 31) }),
    },
    'thanksgiving-us': {
      id: 'thanksgiving-us',
      name: 'Thanksgiving',
      glyph: '\u{1F983}',
      regions: ['us'],
      span: (y) => { const t = nthWeekday(y, 10, 4, 4); return { first: t, last: t }; }, // 4th Thursday of Nov
    },
    'thanksgiving-ca': {
      id: 'thanksgiving-ca',
      name: 'Thanksgiving',
      glyph: '\u{1F983}',
      regions: ['ca'],
      span: (y) => { const t = nthWeekday(y, 9, 1, 2); return { first: t, last: t }; }, // 2nd Monday of Oct
    },
    hanukkah: {
      id: 'hanukkah',
      name: 'Hanukkah',
      glyph: '\u{1F54E}',
      regions: null,
      span: (y) => { const eve = hanukkahEve(y); return { first: eve, last: addDays(eve, 8) }; },
    },
    christmas: {
      id: 'christmas',
      name: 'Christmas',
      glyph: '\u{1F384}',
      regions: null,
      span: (y) => ({ first: day(y, 11, 25), last: day(y, 11, 25) }),
    },
    kwanzaa: {
      id: 'kwanzaa',
      name: 'Kwanzaa',
      glyph: '\u{1F56F}\uFE0F',
      regions: null,
      span: (y) => ({ first: day(y, 11, 26), last: day(y + 1, 0, 1) }), // Dec 26 - Jan 1
    },
    newyear: {
      id: 'newyear',
      name: "New Year's",
      glyph: '\u{1F386}',
      regions: null,
      span: (y) => ({ first: day(y + 1, 0, 1), last: day(y + 1, 0, 1) }), // season year y ends on Jan 1 of y + 1
    },
  };

  // Light/dark palettes. Only four colors each; everything else is derived in cssVars().
  const PALETTES = {
    halloween: {
      dark: { bg: '#120b18', accent: '#ff8a1f', glowA: '#ff8a1f', glowB: '#8b3dff' },
      light: { bg: '#f7f0e8', accent: '#b34700', glowA: '#ff8a1f', glowB: '#6a2bd9' },
    },
    thanksgiving: {
      dark: { bg: '#16100a', accent: '#f0a43a', glowA: '#f0a43a', glowB: '#b5421f' },
      light: { bg: '#f8f1e4', accent: '#9a5300', glowA: '#e08a1f', glowB: '#b5421f' },
    },
    hanukkah: {
      dark: { bg: '#0a1124', accent: '#7fa6ff', glowA: '#7fa6ff', glowB: '#f2d27a' },
      light: { bg: '#eef2fb', accent: '#1f4fbf', glowA: '#4b78e0', glowB: '#d9a920' },
    },
    christmas: {
      dark: { bg: '#0d1410', accent: '#ff6368', glowA: '#ff6368', glowB: '#2fa36b' },
      light: { bg: '#f6f1ec', accent: '#b3261e', glowA: '#d9423a', glowB: '#1b7a4b' },
    },
    kwanzaa: {
      dark: { bg: '#0c120d', accent: '#3fbf6f', glowA: '#3fbf6f', glowB: '#d6453d' },
      light: { bg: '#f1f5ef', accent: '#12703a', glowA: '#2f9e5b', glowB: '#c8352d' },
    },
    newyear: {
      dark: { bg: '#0b0c15', accent: '#f2d06b', glowA: '#f2d06b', glowB: '#9fb0ff' },
      light: { bg: '#f5f3ea', accent: '#7c5e00', glowA: '#d9b23a', glowB: '#5a6fd6' },
    },
  };
  PALETTES['thanksgiving-us'] = PALETTES.thanksgiving;
  PALETTES['thanksgiving-ca'] = PALETTES.thanksgiving;

  // Winter holidays that can blend into one season, in no particular order: the calendar sorts them.
  const WINTER_IDS = ['hanukkah', 'christmas', 'kwanzaa', 'newyear'];

  // ---------- settings ----------

  const DEFAULT_SETTINGS = {
    mode: 'auto',       // 'auto' | 'off' | 'force:<id>' (preview)
    region: 'auto',     // 'auto' | 'us' | 'ca' | 'other'
    winter: 'blend',    // 'blend' | 'individual'
    winterHolidays: WINTER_IDS.slice(),
  };

  function regionFromLocale(locale) {
    const match = /^[a-z]{2,3}(?:-[A-Za-z]{4})?-([A-Za-z]{2})$/.exec(locale || '');
    if (!match) return 'us'; // bare "en": assume US
    const region = match[1].toUpperCase();
    return region === 'US' ? 'us' : region === 'CA' ? 'ca' : 'other';
  }

  // ---------- color helpers ----------

  function hexToRgb(hex) {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function rgbToHex(rgb) {
    return '#' + rgb.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
  }
  function mixHex(a, b, t) {
    const ra = hexToRgb(a);
    const rb = hexToRgb(b);
    return rgbToHex(ra.map((v, i) => v + (rb[i] - v) * t));
  }
  function rgba(hex, alpha) {
    const [r, g, b] = hexToRgb(hex);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }
  function luminance(hex) {
    const [r, g, b] = hexToRgb(hex).map((v) => {
      const c = v / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  function contrast(a, b) {
    const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  }

  // ---------- resolution ----------

  function occurrence(holiday, year) {
    const span = holiday.span(year);
    const win = holiday.window ? holiday.window(year) : { start: addDays(span.first, -LEAD_DAYS), end: span.last };
    return { holiday, first: span.first, last: span.last, start: win.start, end: win.end };
  }

  function staticTheme(holiday) {
    return { id: holiday.id, name: holiday.name, glyph: holiday.glyph, palettes: PALETTES[holiday.id] };
  }

  function candidatesFor(today, settings, region) {
    const out = [];
    const activeRegion = settings.region === 'auto' ? region : settings.region;
    const blendWinter = settings.winter === 'blend';
    const winterSet = new Set(settings.winterHolidays);
    for (const year of [today.getFullYear() - 1, today.getFullYear()]) {
      const winter = [];
      for (const holiday of Object.values(HOLIDAYS)) {
        if (holiday.regions && !holiday.regions.includes(activeRegion)) continue;
        const occ = occurrence(holiday, year);
        if (WINTER_IDS.includes(holiday.id)) {
          if (!winterSet.has(holiday.id)) continue;
          if (blendWinter) { winter.push(occ); continue; }
        }
        out.push(occ);
      }
      if (winter.length) out.push(blendOccurrence(winter));
    }
    return out.filter((c) => today >= c.start && today <= c.end);
  }

  // Several winter holidays folded into one candidate with a palette that follows the calendar.
  function blendOccurrence(list) {
    const stops = list
      .map((o) => ({ mid: addDays(o.first, Math.floor(daysBetween(o.first, o.last) / 2)), id: o.holiday.id }))
      .sort((a, b) => a.mid - b.mid);
    return {
      blend: true,
      first: new Date(Math.min(...list.map((o) => o.first))),
      last: new Date(Math.max(...list.map((o) => o.last))),
      start: new Date(Math.min(...list.map((o) => o.start))),
      end: new Date(Math.max(...list.map((o) => o.end))),
      stops,
    };
  }

  function blendTheme(occ, today) {
    const { stops } = occ;
    let a = stops[0];
    let b = stops[0];
    let t = 0;
    for (let i = 0; i < stops.length; i++) {
      if (today >= stops[i].mid) { a = stops[i]; b = stops[i + 1] || stops[i]; }
    }
    if (a !== b) t = daysBetween(a.mid, today) / daysBetween(a.mid, b.mid);
    const palettes = {};
    for (const scheme of ['dark', 'light']) {
      const pa = PALETTES[a.id][scheme];
      const pb = PALETTES[b.id][scheme];
      palettes[scheme] = {};
      for (const key of Object.keys(pa)) palettes[scheme][key] = mixHex(pa[key], pb[key], t);
    }
    return { id: 'winter', name: 'Winter holidays', glyph: '❄️', palettes };
  }

  // Which candidate shows today? Being inside a holiday's own days beats a lead-in (latest start
  // wins, so Christmas Day beats a Hanukkah that happens to overlap it); otherwise whichever
  // holiday is coming up next; otherwise the one that just passed.
  function pick(candidates, today) {
    const inside = candidates.filter((c) => today >= c.first && today <= c.last);
    if (inside.length) return inside.sort((a, b) => b.first - a.first)[0];
    const upcoming = candidates.filter((c) => c.first >= today).sort((a, b) => a.first - b.first);
    if (upcoming.length) return upcoming[0];
    return candidates.sort((a, b) => b.first - a.first)[0];
  }

  function previewTheme(id, today, settings) {
    if (HOLIDAYS[id]) return staticTheme(HOLIDAYS[id]);
    if (id === 'winter' && WINTER_IDS.length) {
      const year = today.getMonth() >= 6 ? today.getFullYear() : today.getFullYear() - 1;
      const occ = blendOccurrence(WINTER_IDS.map((w) => occurrence(HOLIDAYS[w], year)));
      return blendTheme(occ, day(year, 11, 25));
    }
    return null;
  }

  function resolve(now, rawSettings, region) {
    const settings = Object.assign({}, DEFAULT_SETTINGS, rawSettings);
    if (settings.mode === 'off') return null;
    const today = startOfDay(now);
    if (settings.mode.startsWith('force:')) return previewTheme(settings.mode.slice(6), today, settings);
    const candidates = candidatesFor(today, settings, region || 'us');
    if (!candidates.length) return null;
    const chosen = pick(candidates, today);
    return chosen.blend ? blendTheme(chosen, today) : staticTheme(chosen.holiday);
  }

  // Themes offered in the preview menu.
  function listThemes() {
    const seen = new Set();
    const items = Object.values(HOLIDAYS)
      .filter((h) => !seen.has(h.name) && seen.add(h.name))
      .map((h) => ({ id: h.id, name: h.name, glyph: h.glyph }));
    if (WINTER_IDS.length) items.push({ id: 'winter', name: 'Winter holidays (blended)', glyph: '❄️' });
    return items;
  }

  // CSS custom properties for a resolved theme in the given scheme ('dark' | 'light').
  function cssVars(theme, scheme) {
    const p = theme.palettes[scheme];
    const dark = scheme === 'dark';
    const darkInk = '#14100a';
    const accentText = contrast(p.accent, darkInk) >= contrast(p.accent, '#ffffff') ? darkInk : '#ffffff';
    return {
      '--bg': p.bg,
      '--accent': p.accent,
      '--accent-text': accentText,
      '--focus-ring': dark ? mixHex(p.accent, '#ffffff', 0.35) : p.accent,
      '--accent-surface': rgba(p.accent, dark ? 0.14 : 0.1),
      '--accent-shadow': rgba(p.accent, dark ? 0.2 : 0.16),
      '--ambient-a': rgba(p.glowA, dark ? 0.22 : 0.14),
      '--ambient-b': rgba(p.glowB, dark ? 0.18 : 0.14),
      '--season-glyph': JSON.stringify(theme.glyph),
    };
  }

  const CSS_VAR_NAMES = Object.keys(cssVars(staticTheme(HOLIDAYS.halloween), 'dark'));

  const api = {
    resolve, cssVars, listThemes, regionFromLocale, hanukkahEve, nthWeekday,
    contrast, HOLIDAYS, PALETTES, WINTER_IDS, DEFAULT_SETTINGS, CSS_VAR_NAMES, LEAD_DAYS,
  };
  root.Seasons = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
}(typeof window !== 'undefined' ? window : globalThis));
