# Home Assistant: HDMI Matrix

Custom Home Assistant integration for a generic 4x2 HDMI matrix switcher
(the one at `matrix.local`), talking **directly over the LAN** using the
matrix's own undocumented HTTP protocol — no cloud, no bridge.

## Why not Matter

Matter 1.x has no device type for an N-input/M-output video switcher —
the closest clusters (Media Playback, Content Launcher) don't model
crosspoint routing at all, and this board has no Matter stack to begin
with. Building a bridge would mean translating routing state into
clusters that don't actually represent it, for a device that was never
going to support Matter natively. Direct IP, using the protocol the
matrix's own stock web UI already speaks, is simpler, lower-latency, and
doesn't require any new infrastructure.

## What you get

One HA device ("HDMI Matrix") with:

- **`select.left_source` / `select.right_source`** — pick which input
  (by name) feeds each output. This is the main control; use it in
  automations like "when the Apple TV turns on, route AppleTv to Left".
- **`switch.left_power` / `switch.right_power`** — per-output on/off.
- **`select.<input>_edid`** — EDID profile per input (resolution/HDR/
  channel-count presets), as a `config`-category entity.
- **`button.reboot`** — restart the matrix.
- **`sensor.ip_address` / `sensor.firmware`** — diagnostics.

Polls every 5 seconds via a `DataUpdateCoordinator`, matching the
cadence the matrix's own UI uses.

## Installation

1. Copy `custom_components/hdmi_matrix/` into your Home Assistant config
   directory's `custom_components/` folder (so you end up with
   `config/custom_components/hdmi_matrix/...`).
2. Restart Home Assistant.
3. Settings → Devices & Services → Add Integration → search "HDMI
   Matrix".
4. Enter the host (`matrix.local` or its IP) and the credentials from the
   matrix's own web UI (default `admin` / `admin`).

No YAML required — this is a native config-flow integration.

## Notes

- `matrix_client.py` here is the same protocol client used by the
  companion local web app (`../hdmi-matrix-ui`) — if you build that too,
  both talk to the matrix the same way.
- This class of matrix has a fragile, single-threaded embedded HTTP
  server that can lock up under rapid/concurrent requests. The 5s poll
  interval and serialized requests are chosen to be gentle on it; if the
  device ever stops responding, a power cycle recovers it with no
  settings lost.
- Not yet tested against a live Home Assistant instance in this session
  (the Home Assistant MCP connector used to inspect your instance failed
  to connect) — the code follows standard HA integration patterns
  (DataUpdateCoordinator, config flow, CoordinatorEntity) but you should
  verify entity setup once installed.
