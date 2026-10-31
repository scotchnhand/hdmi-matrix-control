"""Client for the matrix's own embedded HTTP protocol.

Reverse-engineered from the stock web UI (index.html / login.js):

  - State is read via GET /<page>.get<timestamp-ms>, which returns a
    JSONP-ish blob like  VideoCallback({"o1":"2", ... ,});  (note the
    trailing comma before the closing brace -- the firmware's own
    serializer does this on every response).
  - Commands are sent via POST /<page>_set<timestamp-ms> with a body
    that looks like  "#video_d out1 matrix=2"  (space-separated
    key=value pairs after a '#'-prefixed command name). No response
    body is required to be parsed for these.
  - "Login" is POST /login.set<timestamp-ms> with
    "#login id=<base64 user> psd=<base64 pass>". There is no
    Set-Cookie / token issued back -- the device has no real session,
    it just validates the credentials. We still perform it once at
    startup, matching stock behaviour, and retry it if a request ever
    comes back malformed (e.g. after the unit reboots).
"""

from __future__ import annotations

import base64
import http.client
import ipaddress
import json
import re
import threading
import time
import urllib.request

TRAILING_COMMA_RE = re.compile(r",\s*}")

EDID_PRESETS = [
    "Mixer",
    "1920x1200 2CH",
    "1080P 2CH",
    "1080P 6CH",
    "1080P 8CH",
    "4K 420 2CH",
    "4K 420 6CH",
    "4K 420 8CH",
    "4K 444 2CH",
    "4K 444 6CH",
    "4K 444 8CH",
    "4K HDR 10Bit 2CH",
    "4K HDR 10Bit 6CH",
    "4K HDR 10Bit 8CH",
    "Copy Out-A",
    "Copy Out-B",
]

AUDIO_SOURCE_LABELS = {0: "Off", 1: "Out-A", 2: "Out-B"}

NAME_RE = re.compile(r"^[a-zA-Z0-9_]{3,15}$")
CRED_RE = re.compile(r"^[a-zA-Z0-9_]{5,15}$")


class MatrixError(Exception):
    """Raised for anything the matrix itself rejected or returned oddly."""


class MatrixAuthError(MatrixError):
    """Raised when the matrix rejects the username/password."""


# -- input validation ----------------------------------------------------
#
# Commands are space-separated `#command key=value ...` strings, so every
# value spliced into one must be checked first: a value containing a space,
# `=` or `#` could append extra keys or a second command (see #41).

NUM_INPUTS = 4
NUM_OUTPUTS = 2
VALID_GROUPS = ("0",)  # the only account group observed on the device


def validate_port(kind: str, index: int) -> None:
    if kind not in ("in", "out"):
        raise MatrixError("kind must be 'in' or 'out'")
    limit = NUM_INPUTS if kind == "in" else NUM_OUTPUTS
    if isinstance(index, bool) or not isinstance(index, int) or not 1 <= index <= limit:
        raise MatrixError(f"index must be 1-{limit} for kind '{kind}'")


def _ipv4(label: str, value: str) -> str:
    try:
        return str(ipaddress.IPv4Address(str(value).strip()))
    except ValueError as exc:
        raise MatrixError(f"{label} must be a dotted IPv4 address") from exc


def validate_network(ip: str, mask: str, gw: str) -> tuple[str, str, str]:
    """Return normalized (ip, mask, gw), or raise MatrixError."""
    ip, mask, gw = _ipv4("IP", ip), _ipv4("Mask", mask), _ipv4("Gateway", gw)
    try:
        ipaddress.IPv4Network(f"0.0.0.0/{mask}")
    except ValueError as exc:
        raise MatrixError("Mask must be a valid netmask, e.g. 255.255.255.0") from exc
    return ip, mask, gw


def validate_group(group: str) -> None:
    if group not in VALID_GROUPS:
        raise MatrixError(f"group must be one of {', '.join(VALID_GROUPS)}")


class MatrixClient:
    def __init__(self, host: str, username: str = "admin", password: str = "admin", timeout: float = 4.0):
        self.base = f"http://{host}"
        self.username = username
        self.password = password
        self.timeout = timeout
        self._lock = threading.Lock()
        self._logged_in = False

    # -- transport -----------------------------------------------------

    @staticmethod
    def _ts() -> str:
        return str(int(time.time() * 1000))

    @staticmethod
    def _b64(value: str) -> str:
        return base64.b64encode(value.encode("utf-8")).decode("ascii")

    def _request(self, method: str, path: str, body: str | None = None) -> str:
        url = f"{self.base}/{path}{self._ts()}"
        data = body.encode("utf-8") if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        if data is not None:
            req.add_header("Content-Type", "charset=UTF-8")
            req.add_header("ISAJAX", "yes")
        for attempt in range(2):
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    return resp.read().decode("utf-8", errors="replace")
            # Retry only a POST refused before connecting. Timeouts and dropped
            # sockets may happen after the device has applied the command.
            except (OSError, http.client.HTTPException) as exc:
                reason = getattr(exc, "reason", None)
                refused = isinstance(exc, ConnectionRefusedError) or isinstance(reason, ConnectionRefusedError)
                if method == "POST" and attempt == 0 and refused:
                    time.sleep(0.25)
                    continue
                raise MatrixError(f"Could not reach matrix at {self.base}: {exc}") from exc

    @staticmethod
    def _parse_jsonp(text: str, fn_name: str) -> dict:
        text = text.strip()
        prefix = f"{fn_name}("
        if not text.startswith(prefix):
            raise MatrixError(f"Unexpected response from matrix: {text[:160]!r}")
        inner = text[len(prefix):]
        if inner.endswith(");"):
            inner = inner[:-2]
        elif inner.endswith(")"):
            inner = inner[:-1]
        inner = TRAILING_COMMA_RE.sub("}", inner)
        try:
            return json.loads(inner)
        except json.JSONDecodeError as exc:
            raise MatrixError(f"Could not parse matrix response: {text[:160]!r}") from exc

    # -- auth ------------------------------------------------------------

    def login(self) -> dict:
        body = f"#login id={self._b64(self.username)} psd={self._b64(self.password)}"
        text = self._request("POST", "login.set", body)
        data = self._parse_jsonp(text, "settingsLoginCallback")
        if int(data.get("status", 0)) >= 6:
            raise MatrixAuthError(data.get("str", "Login failed"))
        self._logged_in = True
        return data

    def _ensure_login(self):
        if not self._logged_in:
            self.login()

    # -- state (GET) -------------------------------------------------------

    def _get_page(self, page: str, callback: str) -> dict:
        """GET a state page, re-authenticating once after session loss.

        The device can forget its credentials after a reboot initiated by a
        different client. It signals that condition by returning its login
        page (or another malformed response), so retry the read once after a
        fresh login. Transport errors happen before parsing and are allowed to
        propagate without an unnecessary login attempt.
        """
        with self._lock:
            self._ensure_login()
            text = self._request("GET", f"{page}.get")
            try:
                return self._parse_jsonp(text, callback)
            except MatrixError:
                self._logged_in = False
                self.login()
                return self._parse_jsonp(self._request("GET", f"{page}.get"), callback)

    def get_video(self) -> dict:
        return self._get_page("video", "VideoCallback")

    def get_audio(self) -> dict:
        return self._get_page("audio", "AudioCallback")

    def get_edid(self) -> dict:
        return self._get_page("edid", "EdidCallback")

    def get_state(self) -> dict:
        """Aggregate + normalize all three state endpoints into one shape."""
        video = self.get_video()
        audio = self.get_audio()
        edid = self.get_edid()

        inputs = []
        for i in range(1, 5):
            inputs.append({
                "index": i,
                "name": video.get(f"in{i}", f"Input {i}"),
                "edid_preset": int(edid.get(f"i{i}", 0)),
                "edid_detail": edid.get(f"e{int(edid.get(f'i{i}', 0)) + 1}", ""),
            })

        outputs = []
        for i in range(1, 3):
            matrix_idx = int(video.get(f"o{i}", 0))  # 0-indexed source input
            outputs.append({
                "index": i,
                "name": video.get(f"out{i}", f"Output {i}"),
                "input_index": matrix_idx + 1,
                "power": video.get(f"s{i}", "0") == "1",
            })

        arc = int(audio.get("arc", 0))
        ext = int(audio.get("ext", 0))

        return {
            "device": {
                "ip": video.get("ip", ""),
                "account": video.get("account", ""),
                "firmware": video.get("ver", ""),
                "user_group": video.get("group", "0"),
            },
            "inputs": inputs,
            "outputs": outputs,
            "audio": {
                "arc": {"value": arc, "label": AUDIO_SOURCE_LABELS.get(arc, str(arc))},
                "extraction": {"value": ext, "label": AUDIO_SOURCE_LABELS.get(ext, str(ext))},
            },
            "edid_presets": [{"index": i, "name": n} for i, n in enumerate(EDID_PRESETS)],
        }

    # -- commands (POST) -----------------------------------------------

    def _video_set(self, body: str) -> None:
        with self._lock:
            self._ensure_login()
            self._request("POST", "video_set", body)

    def set_route(self, output: int, input_: int) -> None:
        if output not in (1, 2):
            raise MatrixError("output must be 1 or 2")
        if input_ not in (1, 2, 3, 4):
            raise MatrixError("input must be 1-4")
        self._video_set(f"#video_d out{output} matrix={input_ - 1}")

    def set_output_power(self, output: int, on: bool) -> None:
        if output not in (1, 2):
            raise MatrixError("output must be 1 or 2")
        self._video_set(f"#video_d out{output} onoff={1 if on else 0}")

    def rename_port(self, kind: str, index: int, name: str) -> None:
        validate_port(kind, index)
        if not NAME_RE.match(name):
            raise MatrixError("Name must be 3-15 letters, numbers, or underscores")
        self._video_set(f"#port {kind}{index} name={name}")

    def set_edid(self, input_: int, preset: int) -> None:
        if input_ not in (1, 2, 3, 4):
            raise MatrixError("input must be 1-4")
        if not 0 <= preset < len(EDID_PRESETS):
            raise MatrixError(f"preset must be 0-{len(EDID_PRESETS) - 1}")
        with self._lock:
            self._ensure_login()
            self._request("POST", "edid_set", f"#edid_d in{input_} data={preset}")

    def set_audio(self, mode: str, value: int) -> None:
        if mode not in ("arc", "extraction"):
            raise MatrixError("mode must be 'arc' or 'extraction'")
        if value not in (0, 1, 2):
            raise MatrixError("value must be 0 (off), 1 (Out-A), or 2 (Out-B)")
        key = "arc" if mode == "arc" else "dec"
        with self._lock:
            self._ensure_login()
            self._request("POST", "audio_set", f"#audio_d {key}={value}")

    def reboot(self) -> None:
        with self._lock:
            self._ensure_login()
            self._request("POST", "system_set", "#power start=1")
            self._logged_in = False  # device will drop state across reboot

    def factory_reset(self) -> None:
        with self._lock:
            self._ensure_login()
            self._request("POST", "system_set", "#factory0")
            self._logged_in = False

    def set_network(self, ip: str, mask: str, gw: str) -> None:
        ip, mask, gw = validate_network(ip, mask, gw)
        with self._lock:
            self._ensure_login()
            self._request("POST", "ip.set", f"#ip ip={ip} mask={mask} gw={gw}")
            self.base = f"http://{ip}"

    def set_password(self, user: str, password: str, group: str = "0") -> None:
        validate_group(group)
        if not CRED_RE.match(user) or not CRED_RE.match(password):
            raise MatrixError("Username/password must be 5-15 letters, numbers, or underscores")
        with self._lock:
            self._ensure_login()
            self._request("POST", "system_set", f"#register{group} id={user} psd={password}")
            self.username = user
            self.password = password
            self._logged_in = False
