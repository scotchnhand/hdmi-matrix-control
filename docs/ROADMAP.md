# Roadmap

Where this project is and what's planned next. PRs that close one of
these are welcome — see [DEVELOPMENT.md](DEVELOPMENT.md).

## Done

- [x] Reverse-engineer the matrix's embedded HTTP protocol (routing,
      power, rename, EDID, audio ARC/extraction, login) — see
      [PROTOCOL.md](PROTOCOL.md)
- [x] Local web app: zero-dependency Python backend/proxy + dark-mode,
      high-contrast, mobile-first frontend, installable as a PWA
- [x] Home Assistant custom integration talking directly over IP
      (config flow, `select`/`switch`/`button`/`sensor` entities)
- [x] Unit + integration test suite for both (protocol parsing,
      validation, and a real in-process HTTP server test for the web app)
- [x] HA integration tested inside a real in-process Home Assistant
      (`pytest-homeassistant-custom-component`): config flow, entity
      setup, commands, poll failures
- [x] HA integration: audio ARC/extraction selects and port renaming,
      matching the web and iOS apps
- [x] CI: lint, test + coverage, HA manifest validation (`hassfest`), a
      protocol-consistency check between the two `matrix_client.py`
      copies, and weekly CodeQL + Dependabot
- [x] Coordinate web-app reads within one backend process with a short-lived
      state cache; direct polling from separate HA/iOS processes remains a
      documented deployment trade-off

### iOS app

- [x] Native SwiftUI client ([`ios-app/`](../ios-app/)) talking to the
      matrix directly (no backend — native apps aren't subject to CORS),
      with demo mode, Keychain-stored credentials, and a `MatrixKit`
      Swift package tested against the same captured device responses
- [ ] Test against the real device (Local Network permission prompt,
      `matrix.local` resolution, behaviour after a matrix reboot)
- [ ] Bonjour discovery of the matrix instead of typing its host
- [ ] Home Screen widget / Control Center control for one-tap routing
      presets (App Intents)
- [x] Liquid Glass redesign (iOS 26+), with a custom app icon in
      standard / dark / tinted variants
- [ ] Carry the new routing-diagram icon over to the PWA and HA
      integration for a consistent look

## Why this list exists ("continuous improvement" in practice)

The CI pipeline is the enforcement half of continuous improvement
(nothing regresses silently); this list is the direction half (where
effort should go next). Both matter — update this file in the same PR
that closes an item or adds a new one, so it never goes stale. See
[DEVELOPMENT.md](DEVELOPMENT.md) for the PR checklist that includes
exactly that.

## Planned

### Architecture

- [ ] **De-duplicate `matrix_client.py`.** It's currently copy-pasted
      between `hdmi-matrix-ui/backend/` and
      `ha-hdmi-matrix/custom_components/hdmi_matrix/` because HA custom
      components can't depend on an external package without bundling it
      anyway, and the web app has a zero-dependency goal. CI's
      `protocol-consistency` job prevents silent drift in the meantime.
      Options once this gets annoying enough: a tiny vendored-and-synced
      script (`scripts/sync-matrix-client.sh`), or publish it as a small
      PyPI package and vendor it into the HA integration at release time
      (HA custom components can bundle a pinned dependency).
- [ ] Replace `/api/state` polling (web app, every 3s) and the HA
      coordinator's 5s poll with a push model if the device ever exposes
      one — it doesn't currently (no WebSocket/SSE), so this is blocked on
      the hardware, not on us.
- [ ] Optional shared web-backend mode for HA and iOS, so one process is the
      only direct poller talking to the fragile matrix (Phase 2 of the
      multi-client polling plan).

### Web app

- [ ] Multi-matrix support (control more than one unit from one instance)
- [ ] Auth for the local web app itself (currently anyone on your LAN who
      can reach the proxy can control the matrix — fine for a home
      network, not fine if you'd expose this beyond it)

### Home Assistant integration

- [ ] HACS default-store listing (repo topics, brand icon) once the
      integration has been run against a live HA instance. `hacs.json`
      already lets it install as a HACS custom repository.
- [ ] Scene/automation examples in the README (e.g. "Apple TV on → route
      AppleTv to Left")

### CI/CD

- [ ] Enforce a coverage floor (currently reported, not gated — see the
      `test` job in `.github/workflows/ci.yml`) once the suite is mature
      enough that a floor wouldn't just be fighting the tests themselves
- [x] Release automation: release-please release PRs, `vX.Y.Z` tags,
      GitHub Releases with changelog, the HA integration zip and the web
      app image on GHCR (see docs/DEVELOPMENT.md → Releases)
- [x] Bring the iOS app's `MARKETING_VERSION` and PWA service-worker cache
      version under release-please

## Explicitly rejected

- **Matter.** Matter 1.x has no device type for an N-input/M-output video
  switcher — the closest clusters (Media Playback, Content Launcher)
  don't model crosspoint routing, and this board has no Matter stack to
  begin with. A bridge would mean translating state into clusters that
  don't represent it, for no real benefit over direct IP. See
  [ha-hdmi-matrix/README.md](../ha-hdmi-matrix/README.md#why-not-matter).
