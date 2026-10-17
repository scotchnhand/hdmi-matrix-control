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
- [x] Publish the web app as a multi-architecture GHCR image for
      `linux/amd64` and `linux/arm64`, using a non-root container and
      release automation
- [x] Establish `dev` as the development branch and `main` as the release
      branch, with release-please and main-to-dev synchronization

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
- [x] Dark appearance and Liquid Glass redesign (iOS 26+), with a custom
      app icon in standard / dark / tinted variants
- [x] Shared `MatrixKit` package support for macOS 14+ protocol testing
- [ ] Carry the new routing-diagram icon over to the PWA and HA
      integration for a consistent look

### macOS app

- [ ] Add a native SwiftUI macOS application target using the shared
      `MatrixKit` package
- [ ] Refactor UIKit-only theme and input code into cross-platform SwiftUI
      implementations
- [ ] Preserve Liquid Glass on supported macOS releases with a standard
      material fallback on older supported systems
- [ ] Build and validate a Universal 2 release containing both `arm64` and
      `x86_64` slices
- [ ] Add macOS CI, archive, signing, notarization, and installer packaging
- [ ] Add Mac-specific UI tests for routing, connection setup, and destructive
      actions

### tvOS and watchOS apps

- [ ] Add a native tvOS target for living-room routing and source selection
- [ ] Add a watchOS companion target for quick status and favorite routes
- [ ] Add iPhone/watch connectivity, reachability, and handoff behavior
- [ ] Validate the Apple platform targets against a live matrix and offline
      demo mode

### Local Docker hosting

- [x] Publish a multi-architecture web app image for `linux/amd64` and
      `linux/arm64` to GHCR
- [ ] Add a permanent-host Docker Compose stack with persistent configuration,
      restart policy, health checks, and documented LAN binding
- [ ] Add complete Portainer stack documentation, including environment
      variables, updates, logs, rollback, and backup guidance
- [ ] Validate the same Compose deployment flow on CasaOS and ZimaOS
- [ ] Document the security boundary for LAN-only operation and any reverse
      proxy or authentication requirements before internet exposure

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

### Web app

- [x] User-selectable light/dark theme with system preference detection and
      persisted preference
- [ ] Refine the dashboard with Apple-inspired layered materials and subtle
      Liquid Glass-like surfaces while keeping controls accessible and calm
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

- [x] Define an agent-agnostic repository contract in `AGENTS.md`, including
      branch, testing, documentation, and pull-request expectations
- [ ] Apply GitHub protection rulesets to both `main` and `dev`, requiring
      pull requests, passing CI, and no direct pushes
- [ ] Add repository-wide GitHub-flavored Markdown linting and make it a
      required pull-request check
- [ ] Enforce a coverage floor (currently reported, not gated — see the
      `test` job in `.github/workflows/ci.yml`) once the suite is mature
      enough that a floor wouldn't just be fighting the tests themselves
- [x] Release automation: release-please release PRs, `vX.Y.Z` tags,
      GitHub Releases with changelog, the HA integration zip and the web
      app image on GHCR (see docs/DEVELOPMENT.md → Releases)
- [ ] Bring the iOS app's `MARKETING_VERSION` under release-please

## Explicitly rejected

- **Matter.** Matter 1.x has no device type for an N-input/M-output video
  switcher — the closest clusters (Media Playback, Content Launcher)
  don't model crosspoint routing, and this board has no Matter stack to
  begin with. A bridge would mean translating state into clusters that
  don't represent it, for no real benefit over direct IP. See
  [ha-hdmi-matrix/README.md](../ha-hdmi-matrix/README.md#why-not-matter).
