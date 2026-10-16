"""Shared fixtures for the Home Assistant-level tests.

These run the integration inside a real (in-process) Home Assistant via
pytest-homeassistant-custom-component, with the network client swapped for
FakeMatrixClient below -- so nothing ever talks to real hardware.
"""

from __future__ import annotations

import copy
from collections.abc import Generator
from unittest.mock import patch

import pytest
from custom_components.hdmi_matrix.const import CONF_HOST, CONF_PASSWORD, CONF_USERNAME, DOMAIN
from custom_components.hdmi_matrix.matrix_client import EDID_PRESETS, NAME_RE, MatrixError
from pytest_homeassistant_custom_component.common import MockConfigEntry

# Normalized get_state() shape, mirroring the real captured device responses
# used in test_matrix_client.py (AppleTv routed to both outputs, Right off).
INITIAL_STATE = {
    "device": {"ip": "192.168.17.238", "account": "admin", "firmware": "V0.0.11", "user_group": "0"},
    "inputs": [
        {"index": 1, "name": "Windows", "edid_preset": 2, "edid_detail": ""},
        {"index": 2, "name": "MacBook", "edid_preset": 2, "edid_detail": ""},
        {"index": 3, "name": "AppleTv", "edid_preset": 11, "edid_detail": ""},
        {"index": 4, "name": "MacMini", "edid_preset": 2, "edid_detail": ""},
    ],
    "outputs": [
        {"index": 1, "name": "Left", "input_index": 3, "power": True},
        {"index": 2, "name": "Right", "input_index": 3, "power": False},
    ],
    "audio": {
        "arc": {"value": 0, "label": "Off"},
        "extraction": {"value": 1, "label": "Out-A"},
    },
    "edid_presets": [{"index": i, "name": n} for i, n in enumerate(EDID_PRESETS)],
}


class FakeMatrixClient:
    """In-memory stand-in for MatrixClient with the same command surface."""

    def __init__(self, *_args, **_kwargs) -> None:
        self.state = copy.deepcopy(INITIAL_STATE)
        self.fail_with: Exception | None = None
        self.calls: list[tuple] = []

    def _record(self, *call) -> None:
        self.calls.append(call)
        if self.fail_with is not None:
            raise self.fail_with

    def login(self) -> dict:
        self._record("login")
        return {"status": "0"}

    def get_state(self) -> dict:
        self._record("get_state")
        return copy.deepcopy(self.state)

    def set_route(self, output: int, input_: int) -> None:
        self._record("set_route", output, input_)
        self.state["outputs"][output - 1]["input_index"] = input_

    def set_output_power(self, output: int, on: bool) -> None:
        self._record("set_output_power", output, on)
        self.state["outputs"][output - 1]["power"] = on

    def set_edid(self, input_: int, preset: int) -> None:
        self._record("set_edid", input_, preset)
        self.state["inputs"][input_ - 1]["edid_preset"] = preset

    def set_audio(self, mode: str, value: int) -> None:
        self._record("set_audio", mode, value)
        self.state["audio"][mode]["value"] = value

    def rename_port(self, kind: str, index: int, name: str) -> None:
        self._record("rename_port", kind, index, name)
        if not NAME_RE.match(name):
            raise MatrixError("bad name")
        key = "inputs" if kind == "in" else "outputs"
        self.state[key][index - 1]["name"] = name

    def reboot(self) -> None:
        self._record("reboot")


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    yield


@pytest.fixture
def fake_client() -> Generator[FakeMatrixClient]:
    client = FakeMatrixClient()
    with (
        patch("custom_components.hdmi_matrix.MatrixClient", return_value=client),
        patch("custom_components.hdmi_matrix.config_flow.MatrixClient", return_value=client),
    ):
        yield client


@pytest.fixture
def config_entry() -> MockConfigEntry:
    return MockConfigEntry(
        domain=DOMAIN,
        title="HDMI Matrix (192.168.17.238)",
        unique_id="matrix.local",
        data={CONF_HOST: "matrix.local", CONF_USERNAME: "admin", CONF_PASSWORD: "admin"},
    )


@pytest.fixture
async def setup_integration(hass, config_entry, fake_client) -> MockConfigEntry:
    config_entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(config_entry.entry_id)
    await hass.async_block_till_done()
    return config_entry
