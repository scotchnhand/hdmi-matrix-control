'use strict';

// Holiday theme logic for the web app: which holiday (if any) holidays.json
// says is on for a given day and region, and the CSS that applies its
// palette. Pure functions with no DOM access, so the same file runs in the
// browser (as window.HolidayThemes) and under `node --test`
// (hdmi-matrix-ui/frontend-tests). The Swift twin is MatrixKit's
// Holidays.swift; both run the cases in docs/holidays.json.

(function (root) {
  const DAY_MS = 86400000;
  const HEX = /^#[0-9a-f]{6}$/i;

  // Whole days since 1970-01-01 for a civil date. Everything is done in
  // day numbers so time zones and DST never come into it.
  function dayNumber(year, month, day) {
    return Math.round(Date.UTC(year, month - 1, day) / DAY_MS);
  }

  function weekdayOf(dayNo) {
    return (((dayNo + 4) % 7) + 7) % 7; // 0 = Sunday; 1970-01-01 was a Thursday
  }

  function parseDate(iso) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso));
    return match ? { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) } : null;
  }

  function fromLocalDate(date) {
    return { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate() };
  }

  // The day a holiday falls on in `year`, or null for a rule this version
  // doesn't understand (such a holiday is simply never active).
  function occurrence(catalog, holiday, year, depth) {
    const rule = holiday.rule || {};
    if (rule.type === 'fixed') {
      return dayNumber(year, rule.month, rule.day);
    }
    if (rule.type === 'nth-weekday') {
      const first = dayNumber(year, rule.month, 1);
      const shift = (rule.weekday - weekdayOf(first) + 7) % 7;
      return first + shift + (rule.n - 1) * 7;
    }
    if (rule.type === 'offset' && (depth || 0) < 4) {
      const base = (catalog.holidays || []).find((h) => h.id === rule.from);
      const baseDay = base ? occurrence(catalog, base, year, (depth || 0) + 1) : null;
      return baseDay === null ? null : baseDay + rule.days;
    }
    return null;
  }

  function appliesTo(holiday, region) {
    return !Array.isArray(holiday.regions) || holiday.regions.includes(region);
  }

  function isActive(catalog, holiday, dayNo, year) {
    const window = holiday.window || {};
    // The neighbouring years cover windows that straddle New Year.
    for (const y of [year - 1, year, year + 1]) {
      const day = occurrence(catalog, holiday, y);
      if (day !== null && dayNo >= day - (window.before || 0) && dayNo <= day + (window.after || 0)) {
        return true;
      }
    }
    return false;
  }

  // The holiday whose window contains `date` ({year, month, day}) for
  // `region`, or null. Earlier entries in the catalog win an overlap.
  function activeHoliday(catalog, date, region) {
    const dayNo = dayNumber(date.year, date.month, date.day);
    for (const holiday of catalog.holidays || []) {
      if (appliesTo(holiday, region) && isActive(catalog, holiday, dayNo, date.year)) return holiday;
    }
    return null;
  }

  // The holiday that is on now or comes up next -- the default preview.
  function upcomingHoliday(catalog, date, region) {
    const start = dayNumber(date.year, date.month, date.day);
    for (let offset = 0; offset <= 366; offset += 1) {
      const d = new Date((start + offset) * DAY_MS);
      const found = activeHoliday(
        catalog,
        { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() },
        region
      );
      if (found) return found;
    }
    return null;
  }

  // "fr-CA" / "en_US" / "zh-Hans-CN" -> "CA" / "US" / "CN"; '' if the tag
  // carries no region.
  function regionFromLocale(locale) {
    const parts = String(locale || '').split(/[-_]/).slice(1);
    const region = parts.find((part) => /^[A-Za-z]{2}$/.test(part));
    return region ? region.toUpperCase() : '';
  }

  function rgba(hex, alpha) {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
  }

  // Maps the shared palette tokens onto the stylesheet's custom
  // properties. Only palette tokens are touched: status colors (--on,
  // --danger), surfaces and text keep their values, so the
  // prefers-contrast / reduced-transparency fallbacks keep working.
  function cssVariables(palette, scheme) {
    const dark = scheme === 'dark';
    return {
      '--bg': palette.bg,
      '--accent': palette.accent,
      '--accent-text': palette['accent-text'],
      '--focus-ring': palette.accent,
      '--accent-surface': rgba(palette.accent, dark ? 0.14 : 0.1),
      '--accent-shadow': rgba(palette.accent, dark ? 0.2 : 0.16),
      '--ambient-a': rgba(palette['glow-a'], dark ? 0.18 : 0.12),
      '--ambient-b': rgba(palette['glow-b'], dark ? 0.12 : 0.1),
    };
  }

  function validPalette(palette, tokens) {
    return Boolean(palette) && tokens.every((token) => HEX.test(palette[token] || ''));
  }

  // A stylesheet that overrides the palette for both color schemes, using
  // the same selectors as styles.css so the light/dark toggle keeps
  // working. Returns '' if the holiday's palette is unusable.
  function themeCss(catalog, holiday) {
    const tokens = catalog.tokens || [];
    const palette = (holiday && holiday.palette) || {};
    if (!validPalette(palette.dark, tokens) || !validPalette(palette.light, tokens)) return '';
    const block = (scheme) =>
      Object.entries(cssVariables(palette[scheme], scheme))
        .map(([name, value]) => `${name}: ${value};`)
        .join(' ');
    return [
      `:root { ${block('dark')} }`,
      `:root[data-theme="light"] { ${block('light')} }`,
      `@media (prefers-color-scheme: light) { :root:not([data-theme="dark"]) { ${block('light')} } }`,
    ].join('\n');
  }

  const api = {
    activeHoliday,
    upcomingHoliday,
    regionFromLocale,
    cssVariables,
    themeCss,
    parseDate,
    fromLocalDate,
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.HolidayThemes = api;
})(typeof self !== 'undefined' ? self : globalThis);
