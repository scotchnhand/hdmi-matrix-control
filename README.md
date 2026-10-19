# HDMI Matrix

[![CI](https://github.com/scotchnhand/hdmi-matrix-control/actions/workflows/ci.yml/badge.svg)](https://github.com/scotchnhand/hdmi-matrix-control/actions/workflows/ci.yml)
[![CodeQL](https://github.com/scotchnhand/hdmi-matrix-control/actions/workflows/codeql.yml/badge.svg)](https://github.com/scotchnhand/hdmi-matrix-control/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A modern control surface for a generic 4-input / 2-output HDMI matrix
switcher — the kind of cheap, white-label AV-over-HDMI box with a circa-2015
embedded web UI and no public API documentation. This repo replaces that UI
with two things, both talking directly to the matrix over your LAN (no
cloud, no vendor app):

| Component | What it provides |
|---|---|
| **[`hdmi-matrix-ui/`](hdmi-matrix-ui/)** | A local web app — zero-dependency Python backend + a dark-mode, high-contrast, installable-as-a-PWA frontend |
| **[`ha-hdmi-matrix/`](ha-hdmi-matrix/)** | A Home Assistant custom integration — `select`/`switch`/`button`/`sensor` entities for routing, power, and EDID |
| **[`ios-app/`](ios-app/)** | A native SwiftUI iPhone/iPad app (iOS 26, Liquid Glass) that talks to the matrix directly — no backend needed. [User guide](docs/ios-guide/README.md) |

<p align="center">
  <img src="docs/images/web-app-dark.jpg" width="47%" alt="Web app, dark mode" />
  <img src="docs/images/web-app-light.jpg" width="47%" alt="Web app, light mode" />
</p>

## Why this exists

The matrix's own web UI is a single unauthenticated-feeling HTML page from
2015, with no mobile layout, no dark mode, and a routing model (tiny
checkboxes + an "ON"/"OFF" text button) that's miserable to use from a
couch. It also has **no public API** — everything here was built by
reverse-engineering its actual wire protocol (JSONP-ish polling + raw POST
commands). That protocol is fully documented in
**[docs/PROTOCOL.md](docs/PROTOCOL.md)**.

## Quick start

**Web app:**

```bash
cd hdmi-matrix-ui/backend
cp config.example.json config.json   # edit host/username/password
python3 server.py
```

Open `http://localhost:8765` (or your LAN IP, printed on startup) and
optionally "Add to Home Screen" on your phone. See
[hdmi-matrix-ui/README.md](hdmi-matrix-ui/README.md) for the mock-mode
preview (no hardware required) and full config options.

**Web app in Docker** (Portainer, ZimaOS, or any Docker host):

```bash
docker run -d --name hdmi-matrix-ui --restart unless-stopped -p 8765:8765 \
  -e MATRIX_HOST=<matrix-ip> ghcr.io/scotchnhand/hdmi-matrix-control:latest
```

See **[docs/DOCKER.md](docs/DOCKER.md)** for Compose, Portainer, and ZimaOS
instructions.

**Home Assistant:**

Install through HACS as a custom repository, or unzip `hdmi_matrix.zip`
from the [latest release](https://github.com/scotchnhand/hdmi-matrix-control/releases/latest)
into your HA config's `custom_components/hdmi_matrix/`. Restart HA, then Settings → Devices & Services → Add
Integration → "HDMI Matrix". See
[ha-hdmi-matrix/README.md](ha-hdmi-matrix/README.md) for the full entity
list and why this uses direct IP instead of Matter.

## Repo structure

Every entry below links directly to the corresponding file or directory on
GitHub:

- [`hdmi-matrix-ui/`](hdmi-matrix-ui/) — local web app
  - [`backend/`](hdmi-matrix-ui/backend/) — zero-dependency Python proxy and tests
  - [`frontend/`](hdmi-matrix-ui/frontend/) — installable web UI and PWA assets
  - [`README.md`](hdmi-matrix-ui/README.md) — web-app setup and configuration
- [`ha-hdmi-matrix/`](ha-hdmi-matrix/) — Home Assistant integration
  - [`custom_components/hdmi_matrix/`](ha-hdmi-matrix/custom_components/hdmi_matrix/) — integration source
  - [`tests/`](ha-hdmi-matrix/tests/) — Home Assistant integration tests
  - [`README.md`](ha-hdmi-matrix/README.md) — installation and entity reference
- [`ios-app/`](ios-app/) — native SwiftUI app
  - [`HDMIMatrix/`](ios-app/HDMIMatrix/) — app target
  - [`MatrixKit/`](ios-app/MatrixKit/) — reusable Swift protocol client
  - [`README.md`](ios-app/README.md) — Xcode setup and testing
- [`docs/`](docs/) — protocol, development, roadmap, and deployment documentation
  - [`PROTOCOL.md`](docs/PROTOCOL.md) — reverse-engineered wire protocol
  - [`ROADMAP.md`](docs/ROADMAP.md) — what's done, planned, and deliberately rejected
  - [`DEVELOPMENT.md`](docs/DEVELOPMENT.md) — setup, testing, and branch conventions
  - [`DOCKER.md`](docs/DOCKER.md) — Docker, Portainer, and ZimaOS deployment
- [`.github/`](.github/) — workflows, issue forms, and pull-request templates
  - [`workflows/`](.github/workflows/) — CI, release, CodeQL, and dependency updates
  - [`ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) — bug-report and feature-request forms
  - [`PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md)
- [`AGENTS.md`](AGENTS.md) — repository guidelines for contributors and coding agents
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contribution workflow
- [`LICENSE`](LICENSE) — MIT license

## Development, testing, and contributing

Both subprojects have a real test suite (protocol parsing against captured
real-device responses, plus an in-process HTTP server test for the web
app) that runs in CI on every push/PR, alongside linting, Home Assistant
manifest validation, weekly CodeQL scanning, and Dependabot. See
**[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** for how to run everything
locally, and **[CONTRIBUTING.md](CONTRIBUTING.md)** / the issue templates
for filing bugs and feature requests. **[docs/ROADMAP.md](docs/ROADMAP.md)**
tracks what's planned next (and why a few things, like Matter support,
were deliberately ruled out).

## A hardware note

This class of matrix has a fragile, single-threaded embedded HTTP server
that can lock up under rapid or concurrent requests. If either client
shows "connection lost" and stays that way, power-cycle the matrix
(unplug/replug) — no settings are lost. Both [`matrix_client.py`](hdmi-matrix-ui/backend/matrix_client.py)
implementations serialize requests to the device specifically to minimize
this. The web backend also coalesces reads from multiple open tabs for a
short interval. Home Assistant and the iOS app are separate direct pollers,
so a deployment with several clients should choose one direct poller where
possible. Details are in [docs/PROTOCOL.md](docs/PROTOCOL.md) and the
[roadmap](docs/ROADMAP.md#architecture).

## License

[MIT](LICENSE)
