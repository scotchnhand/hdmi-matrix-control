# HDMI Matrix UI

A modern, dark-mode/high-contrast, mobile-friendly replacement for the
stock web UI of a generic 4x2 HDMI matrix switcher (the one at
`matrix.local`). Installable as a PWA so it behaves like a native app on
your phone's home screen.

## Why a backend is needed

The matrix's embedded web server sends no CORS headers, so a browser
blocks any page not actually served by the matrix from calling its API.
`backend/server.py` is a small local proxy: it serves the frontend and
translates a handful of clean `/api/*` endpoints into the matrix's own
undocumented protocol (reverse-engineered from its stock UI — see
`backend/matrix_client.py` for the full writeup).

It has **zero third-party dependencies** — just the Python 3 standard
library — so there's nothing to `pip install`.

## Running it

```bash
cd backend
cp config.example.json config.json   # edit host/username/password if needed
python3 server.py
```

Then open `http://localhost:8765` (or, from your phone/tablet on the same
network, `http://<this-machine's-LAN-IP>:8765` — the server prints both
URLs on startup). On iOS/Android, use the browser's "Add to Home Screen"
to install it as a standalone app icon.

### Previewing without the hardware

Set `"matrix_host": "mock"` in `config.json` (or `MATRIX_HOST=mock`) to run
against an in-memory fake matrix — useful for trying the UI or developing
without the real device online.

## Configuration

Edit `backend/config.json` (copy from `config.example.json`) or set
environment variables:

| config.json key | env var | default |
|---|---|---|
| `matrix_host` | `MATRIX_HOST` | `matrix.local` |
| `matrix_username` | `MATRIX_USERNAME` | `admin` |
| `matrix_password` | `MATRIX_PASSWORD` | `admin` |
| `listen_host` | `LISTEN_HOST` | `0.0.0.0` |
| `listen_port` | `LISTEN_PORT` | `8765` |

## A note on the hardware

This class of matrix (cheap, white-label, single-threaded embedded HTTP
server) can lock up its web server under rapid or concurrent requests —
it happened once while reverse-engineering the protocol for this project.
If the UI shows "Connection lost" and stays that way, power-cycle the
matrix (unplug/replug); no settings are lost, it's just the HTTP listener
recovering. The backend already serializes all requests to the device to
minimize this.

## Project layout

```text
backend/
  server.py          stdlib HTTP server: serves frontend/, proxies /api/*
  matrix_client.py    the reverse-engineered matrix protocol
  mock_client.py       in-memory stand-in for previewing/demoing
  config.py / config.example.json
frontend/
  index.html / styles.css / app.js
  manifest.json / sw.js   PWA install + offline app-shell
  icons/
```

## Running it permanently (optional)

To have it start on boot (macOS, via `launchd`), or run it on a
Raspberry Pi / always-on box on your network instead of your laptop, wrap
the `python3 server.py` command in your OS's usual service manager — the
server itself needs no special privileges beyond binding its port.

For a Docker host with a persistent restart policy, use the repository's
`compose.yaml` and see [`docs/DOCKER.md`](../docs/DOCKER.md). The web PWA has a
dark/light theme toggle that persists locally; the native Apple clients use the
same local-first appearance model.
