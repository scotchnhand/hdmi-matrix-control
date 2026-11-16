# Holiday themes

The web app and the iOS app can swap in a seasonal palette on holidays. It is
**off by default** and opt-in per device. The Home Assistant integration has no
UI of its own, so it is not involved.

| Setting | Web app | iOS app |
| --- | --- | --- |
| Where | Advanced → Appearance | Device tab → Appearance |
| Holiday themes | Off / Auto / Always | Off / Auto / Always |
| Region | Auto (browser language) / US / Canada | Automatic (device region) / US / Canada |

- **Off** — the normal look.
- **Auto** — the theme shows on the holiday's dates and goes away afterwards.
- **Always** — pick any theme to preview it, whatever the date.

The region only matters for holidays that differ by country: US Thanksgiving is
the 4th Thursday of November, Canadian Thanksgiving the 2nd Monday of October.
Everything is computed on the device from the local date; there are no network
calls beyond the web app loading its own `holidays.json`.

## Holidays

| Holiday | Date | Theme shows |
| --- | --- | --- |
| Halloween | October 31 | October 21–31 |
| Thanksgiving (CA) | 2nd Monday of October | the Friday before through Monday |
| Thanksgiving (US) | 4th Thursday of November | Monday through Thursday |
| Black Friday | day after US Thanksgiving | Friday through Sunday |
| Cyber Monday | Monday after US Thanksgiving | that day |
| Christmas | December 25 | December 11–26 |
| New Year's | January 1 | December 31 – January 1 |
| Valentine's Day | February 14 | February 8–14 |

## `holidays.json`

`docs/holidays.json` is the single definition both clients use. Two
byte-identical copies ship with the apps (CI fails if they drift):

- `hdmi-matrix-ui/frontend/holidays.json`
- `ios-app/MatrixKit/Sources/MatrixKit/Resources/holidays.json`

After editing the source, copy it over both and run the tests:

```bash
cp docs/holidays.json hdmi-matrix-ui/frontend/holidays.json
cp docs/holidays.json ios-app/MatrixKit/Sources/MatrixKit/Resources/holidays.json
node --test hdmi-matrix-ui/frontend-tests/*.test.js
(cd ios-app/MatrixKit && swift test)
```

Each entry in `holidays` has:

| Field | Meaning |
| --- | --- |
| `id`, `name` | Stable identifier and display name. |
| `regions` | Optional list of regions (`US`, `CA`) the holiday is limited to. Omit for everywhere. |
| `rule` | `{"type": "fixed", "month", "day"}`, `{"type": "nth-weekday", "month", "weekday", "n"}` (weekday 0 = Sunday), or `{"type": "offset", "from": <id>, "days"}`. |
| `window` | `before` / `after`: days around the holiday on which the theme shows. |
| `palette` | `dark` and `light`, each with exactly the tokens listed in `tokens`. |

Order matters: when two windows overlap, the earlier entry wins. A client that
meets a rule type it doesn't know treats that holiday as never active.

`cases` holds the shared test cases (`active`, `upcoming`, `locale_regions`).
The web suite (`hdmi-matrix-ui/frontend-tests/holidays.test.js`) and MatrixKit's
`HolidayFixtureTests.swift` both run them, the same way
`docs/protocol-fixtures.json` keeps the protocol clients in step. Add a case
whenever you add a holiday or change a rule.

## Palette tokens

A theme overrides palette tokens only:

| Token | Web (`styles.css`) | iOS |
| --- | --- | --- |
| `accent` | `--accent`, `--focus-ring`, and the tints derived from it | app tint |
| `accent-text` | `--accent-text` | — |
| `bg` | `--bg` | bottom of the backdrop gradient (the top leans toward `glow-a`) |
| `glow-a`, `glow-b` | `--ambient-a`, `--ambient-b` | the two backdrop glows |

Status colors (`--on`, `--danger`), surfaces, text, and the iOS output 1 /
output 2 colors are never themed. The web tests enforce contrast: for every
theme and color scheme, each pair the palette takes part in (accent text on
accent, accent on the opaque surfaces and the background, text on the
background) must be at least as strong as the default theme's, or 7:1 where the
default exceeds that. Because surfaces are untouched, the
`prefers-contrast: more` and reduced-transparency fallbacks behave as before.

Not in v1: app icon or PWA `theme-color` changes.
