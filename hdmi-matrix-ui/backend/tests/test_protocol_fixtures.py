"""Shared protocol cases (docs/protocol-fixtures.json), run against this
copy of matrix_client.py. MatrixKit runs the same cases in Swift.
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent))

from matrix_client import MatrixClient, MatrixError  # noqa: E402


def _find_fixtures() -> Path:
    for parent in Path(__file__).resolve().parents:
        candidate = parent / "docs" / "protocol-fixtures.json"
        if candidate.exists():
            return candidate
    raise FileNotFoundError("docs/protocol-fixtures.json not found above this test")


FIXTURES = json.loads(_find_fixtures().read_text())

CALLS = {
    "set_route": lambda c, a: c.set_route(a["output"], a["input"]),
    "set_output_power": lambda c, a: c.set_output_power(a["output"], a["on"]),
    "rename": lambda c, a: c.rename_port(a["kind"], a["index"], a["name"]),
    "set_edid": lambda c, a: c.set_edid(a["input"], a["preset"]),
    "set_audio": lambda c, a: c.set_audio(a["mode"], a["value"]),
    "set_network": lambda c, a: c.set_network(a["ip"], a["mask"], a["gw"]),
    "set_credentials": lambda c, a: c.set_password(a["user"], a["password"]),
    "reboot": lambda c, a: c.reboot(),
    "factory_reset": lambda c, a: c.factory_reset(),
}


class ProtocolFixtureTests(unittest.TestCase):
    """Runs the cases in docs/protocol-fixtures.json, which MatrixKit's
    ProtocolFixtureTests.swift runs too, so the clients can't drift apart."""

    def client(self) -> MatrixClient:
        client = MatrixClient("matrix.test")
        client._logged_in = True
        return client

    def test_every_call_is_covered(self):
        calls = {case["call"] for case in FIXTURES["commands"] + FIXTURES["rejections"]}
        self.assertEqual(calls - CALLS.keys(), set())

    def test_commands_produce_expected_wire_strings(self):
        for case in FIXTURES["commands"]:
            with self.subTest(call=case["call"], args=case["args"]):
                client = self.client()
                with patch.object(client, "_request", return_value="") as request:
                    CALLS[case["call"]](client, case["args"])
                request.assert_called_once_with("POST", case["page"], case["body"])

    def test_rejections_send_nothing(self):
        for case in FIXTURES["rejections"]:
            with self.subTest(call=case["call"], args=case["args"]):
                client = self.client()
                with patch.object(client, "_request") as request, self.assertRaises(MatrixError):
                    CALLS[case["call"]](client, case["args"])
                request.assert_not_called()

    def test_state_normalization(self):
        responses = FIXTURES["responses"]
        pages = {"video.get": responses["video"], "audio.get": responses["audio"], "edid.get": responses["edid"]}
        client = self.client()
        with patch.object(client, "_request", side_effect=lambda method, path, body=None: pages[path]):
            state = client.get_state()
        expected = FIXTURES["state"]
        self.assertEqual(state["device"]["firmware"], expected["firmware"])
        self.assertEqual(
            [{k: i[k] for k in ("index", "name", "edid_preset")} for i in state["inputs"]],
            expected["inputs"],
        )
        self.assertEqual(
            [{k: o[k] for k in ("index", "name", "input_index", "power")} for o in state["outputs"]],
            expected["outputs"],
        )
        self.assertEqual(
            {"arc": state["audio"]["arc"]["value"], "extraction": state["audio"]["extraction"]["value"]},
            expected["audio"],
        )


if __name__ == "__main__":
    unittest.main()
