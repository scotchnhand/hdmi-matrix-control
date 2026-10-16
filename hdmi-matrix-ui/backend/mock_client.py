"""In-memory stand-in for MatrixClient with the exact same surface.

Used by server.py when matrix_host == "mock", so the UI can be built and
demoed without the physical device on the network (handy right now since the
real unit's embedded HTTP server is wedged and needs a power cycle, and handy
generally for previewing the UI).
"""

from __future__ import annotations

from matrix_client import AUDIO_SOURCE_LABELS, CRED_RE, EDID_PRESETS, NAME_RE, MatrixError


class MockMatrixClient:
    def __init__(self, host="mock", username="admin", password="admin", timeout=4):
        self._inputs = {1: "Windows", 2: "MacBook", 3: "AppleTv", 4: "MacMini"}
        self._outputs = {1: "Left", 2: "Right"}
        self._routes = {1: 3, 2: 3}
        self._power = {1: True, 2: True}
        self._edid = {1: 15, 2: 1, 3: 2, 4: 15}
        self._audio = {"arc": 0, "extraction": 1}

    def login(self):
        return {"status": 0}

    def get_state(self) -> dict:
        inputs = [{
            "index": i,
            "name": self._inputs[i],
            "edid_preset": self._edid[i],
            "edid_detail": EDID_PRESETS[self._edid[i]],
        } for i in range(1, 5)]
        outputs = [{
            "index": i,
            "name": self._outputs[i],
            "input_index": self._routes[i],
            "power": self._power[i],
        } for i in range(1, 3)]
        return {
            "device": {"ip": "192.168.17.238", "account": "admin", "firmware": "V0.0.11 (mock)", "user_group": "0"},
            "inputs": inputs,
            "outputs": outputs,
            "audio": {
                "arc": {"value": self._audio["arc"], "label": AUDIO_SOURCE_LABELS[self._audio["arc"]]},
                "extraction": {"value": self._audio["extraction"], "label": AUDIO_SOURCE_LABELS[self._audio["extraction"]]},
            },
            "edid_presets": [{"index": i, "name": n} for i, n in enumerate(EDID_PRESETS)],
        }

    def set_route(self, output, input_):
        if output not in self._outputs or input_ not in self._inputs:
            raise MatrixError("invalid output/input")
        self._routes[output] = input_

    def set_output_power(self, output, on):
        self._power[output] = bool(on)

    def rename_port(self, kind, index, name):
        if not NAME_RE.match(name):
            raise MatrixError("Name must be 3-15 letters, numbers, or underscores")
        (self._inputs if kind == "in" else self._outputs)[index] = name

    def set_edid(self, input_, preset):
        if not 0 <= preset < len(EDID_PRESETS):
            raise MatrixError("invalid preset")
        self._edid[input_] = preset

    def set_audio(self, mode, value):
        self._audio[mode] = value

    def reboot(self):
        pass

    def factory_reset(self):
        self._inputs = {1: "Windows", 2: "MacBook", 3: "AppleTv", 4: "MacMini"}
        self._outputs = {1: "Left", 2: "Right"}
        self._routes = {1: 3, 2: 3}
        self._power = {1: True, 2: True}
        self._edid = {1: 15, 2: 1, 3: 2, 4: 15}
        self._audio = {"arc": 0, "extraction": 1}

    def set_network(self, ip, mask, gw):
        pass

    def set_password(self, user, password, group="0"):
        if not CRED_RE.match(user) or not CRED_RE.match(password):
            raise MatrixError("Username/password must be 5-15 letters, numbers, or underscores")
