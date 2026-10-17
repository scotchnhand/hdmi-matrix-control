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
  Stays usable while the output is off, so you can pick the source before
  powering the display on.
- **`switch.left_power` / `switch.right_power`** — per-output on/off.
- **`select.audio_return_arc` / `select.audio_extraction`** — which
  output's audio feeds the ARC / extraction port: `Off` or an output name
  (e.g. `Left`). The `source` attribute shows the input currently routed
  to that output — i.e. what you'll actually hear.
- **`text.input_1_name` … `text.output_2_name`** — rename ports (3–15
  letters, numbers, or underscores, the device's own rule). Names must be
  unique within inputs / outputs, since the selects above use them as
  options. Renaming changes those options but never any entity IDs.
- **`select.<input>_edid`** — EDID profile per input (resolution/HDR/
  channel-count presets), as a `config`-category entity.
- **`button.reboot`** — restart the matrix.
- **`sensor.ip_address` / `sensor.firmware`** — diagnostics.

Entity IDs are prefixed with the device name, e.g.
`select.hdmi_matrix_left_source`.

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
- Tested inside a real in-process Home Assistant via
  `pytest-homeassistant-custom-component` (config flow, entity setup, every
  command, polling failures — see `tests/`), but with the matrix itself
  faked. It hasn't yet been run against real hardware from a live HA
  install, so report anything odd via the bug template.

## Running the tests

Needs Python 3.14+ (current Home Assistant's minimum):

```bash
cd ha-hdmi-matrix
python3.14 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest tests -v
```
