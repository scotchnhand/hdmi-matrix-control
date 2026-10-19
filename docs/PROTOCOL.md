# The matrix's wire protocol

This documents the undocumented HTTP protocol spoken by the matrix's
embedded web server, reverse-engineered from its stock UI (view-source
and network-tab archaeology — there is no vendor datasheet for this). Both
`hdmi-matrix-ui/backend/matrix_client.py` and
`ha-hdmi-matrix/custom_components/hdmi_matrix/matrix_client.py` implement
exactly this (see [ROADMAP.md](ROADMAP.md) for the plan to de-duplicate
the two copies), and so does the iOS app's
`ios-app/MatrixKit/Sources/MatrixKit/MatrixClient.swift`.

**[`protocol-fixtures.json`](protocol-fixtures.json)** is the executable
version of this document: captured device responses, the exact wire
command each client call must send, and inputs every client must reject.
All three clients' test suites run it, so a protocol change starts there.

## Shape

- **State reads** are `GET /<page>.get<unix-ms-timestamp>` and return a
  JSONP-style blob, e.g.:

  ```
  VideoCallback({"o1":"2",    "o2":"2",    "s1":"1",    "s2":"1",
  "group":"0",    "account":"admin",    "ip":"192.168.17.238",
  "port":"001011",    "in1":"Windows",   "in2":"MacBook",
  "in3":"AppleTv",   "in4":"MacMini",   "out1":"Left",
  "out2":"Right",   "ver":"V0.0.11",    });
  ```

  Note the trailing comma before the closing `}` — the firmware's own
  serializer does this on every response, on every endpoint. The client
  strips it before `json.loads`.

- **Commands** are `POST /<page>_set<unix-ms-timestamp>` with a body like
  `#video_d out1 matrix=2` — a `#`-prefixed command name followed by
  space-separated `key=value` pairs. No meaningful response body.

- **"Auth"** is `POST /login.set<ts>` with
  `#login id=<base64 username> psd=<base64 password>`. There is no
  `Set-Cookie` or token issued back — the device has no real session, it
  just validates the credentials against its own config each time. The
  stock UI re-sends this on every page load (reading the creds back out of
  a plaintext cookie); our clients do it once at startup and again if a
  request ever comes back malformed (e.g. after a reboot).

## Endpoints

| Endpoint | Method | Body | Purpose |
|---|---|---|---|
| `video.get` | GET | — | Routing, power, port names, device IP/account/firmware |
| `audio.get` | GET | — | ARC and audio-extraction source (0=off, 1=Out-A, 2=Out-B) |
| `edid.get` | GET | — | EDID preset assigned per input + the resulting negotiated mode text |
| `login.set` | POST | `#login id=<b64> psd=<b64>` | Validate credentials |
| `video_set` | POST | `#video_d out<N> matrix=<0-indexed input>` | Route input to output |
| `video_set` | POST | `#video_d out<N> onoff=<0\|1>` | Output power |
| `video_set` | POST | `#port in<N>\|out<N> name=<name>` | Rename a port (`^[a-zA-Z0-9_]{3,15}$`) |
| `edid_set` | POST | `#edid_d in<N> data=<0-15>` | Assign an EDID preset to an input |
| `audio_set` | POST | `#audio_d arc=<0\|1\|2>` | ARC source |
| `audio_set` | POST | `#audio_d dec=<0\|1\|2>` | Audio-extraction source (note: field is `ext` on read, `dec` on write) |
| `system_set` | POST | `#power start=1` | Reboot |
| `system_set` | POST | `#factory0` | Factory reset |
| `system_set` | POST | `#register<group> id=<user> psd=<pass>` | Change credentials (`^[a-zA-Z0-9_]{5,15}$`) |
| `ip.set` | POST | `#ip ip=<ip> mask=<mask> gw=<gw>` | Static network config |

## The 16 EDID presets

Index → description (fixed firmware list, not returned dynamically by the
device — see `EDID_PRESETS` in `matrix_client.py`):

```
00 Mixer              04 1080P 8CH          08 4K 444 2CH         12 4K HDR 10Bit 6CH
01 1920x1200 2CH      05 4K 420 2CH         09 4K 444 6CH         13 4K HDR 10Bit 8CH
02 1080P 2CH          06 4K 420 6CH         10 4K 444 8CH         14 Copy Out-A
03 1080P 6CH          07 4K 420 8CH         11 4K HDR 10Bit 2CH   15 Copy Out-B
```

## Known hardware quirk

This class of matrix (cheap, white-label, single-threaded embedded HTTP
server) **can lock up its web server under rapid or concurrent requests**
— it happened once during development. It keeps answering ICMP ping but
stops answering HTTP entirely. A power cycle (unplug/replug) recovers it
with no settings lost. Both `matrix_client.py` implementations serialize
all requests to the device (a single lock around every call) specifically
to minimize triggering this.

The device can also forget its login state after an external reboot or power
cycle while continuing to accept HTTP connections. Each Python client treats
a malformed state response as session loss, logs in once, and retries that
same read once. A second malformed response is returned as an error; transport
failures do not trigger an extra login attempt. The Swift client follows the
same one-retry policy.

## The web app's `/api/*` layer

`hdmi-matrix-ui/backend/server.py` exposes a clean JSON API that wraps the
protocol above — this is what `frontend/app.js` actually calls:

| Route | Method | Body | Returns |
|---|---|---|---|
| `/api/state` | GET | — | Full normalized state (see `MatrixClient.get_state()`) |
| `/api/route` | POST | `{output, input}` | New state |
| `/api/output-power` | POST | `{output, on}` | New state |
| `/api/rename` | POST | `{kind: "in"\|"out", index, name}` | New state |
| `/api/edid` | POST | `{input, preset}` | New state |
| `/api/audio` | POST | `{mode: "arc"\|"extraction", value}` | New state |
| `/api/network` | POST | `{ip, mask, gw}` | New state |
| `/api/system/reboot` | POST | — | New state |
| `/api/system/factory-reset` | POST | — | New state |
| `/api/system/password` | POST | `{user, password}` | New state |

Every POST returns the fresh aggregated state (same shape as `/api/state`)
so the frontend never has to guess at the result of an action.

The web backend coalesces `/api/state` reads from multiple browser tabs for a
short TTL and invalidates that cache after a successful command. This reduces
load within one backend process, but it cannot coordinate independent HA, iOS,
and web-backend processes; deployments should prefer one direct poller when
the hardware is under load.

## Home Assistant entities

See [ha-hdmi-matrix/README.md](../ha-hdmi-matrix/README.md) for the full
entity list; they all read/write through the same `MatrixClient` via a
`DataUpdateCoordinator` polling every 5 seconds.
