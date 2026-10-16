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
import json
import re
import threading
import time
import urllib.error
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
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return resp.read().decode("utf-8", errors="replace")
        except urllib.error.URLError as exc:
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
            raise MatrixError(data.get("str", "Login failed"))
        self._logged_in = True
        return data

    def _ensure_login(self):
        if not self._logged_in:
            self.login()

    # -- state (GET) -------------------------------------------------------

    def get_video(self) -> dict:
        with self._lock:
            self._ensure_login()
            return self._parse_jsonp(self._request("GET", "video.get"), "VideoCallback")

    def get_audio(self) -> dict:
        with self._lock:
            self._ensure_login()
            return self._parse_jsonp(self._request("GET", "audio.get"), "AudioCallback")

    def get_edid(self) -> dict:
        with self._lock:
            self._ensure_login()
            return self._parse_jsonp(self._request("GET", "edid.get"), "EdidCallback")

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
        if kind not in ("in", "out"):
            raise MatrixError("kind must be 'in' or 'out'")
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
        with self._lock:
            self._ensure_login()
            self._request("POST", "ip.set", f"#ip ip={ip} mask={mask} gw={gw}")

    def set_password(self, user: str, password: str, group: str = "0") -> None:
        if not CRED_RE.match(user) or not CRED_RE.match(password):
            raise MatrixError("Username/password must be 5-15 letters, numbers, or underscores")
        with self._lock:
            self._ensure_login()
            self._request("POST", "system_set", f"#register{group} id={user} psd={password}")
