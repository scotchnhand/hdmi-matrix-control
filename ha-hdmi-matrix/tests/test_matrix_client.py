"""Protocol-level tests for the HA integration's copy of matrix_client.py.

This file is intentionally near-identical to
hdmi-matrix-ui/backend/tests/test_matrix_client.py: the two integrations
each carry their own copy of the client (see docs/ROADMAP.md for the plan
to de-duplicate that), and CI runs both copies' tests so the two can never
silently drift apart without a test failure somewhere.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent / "custom_components" / "hdmi_matrix"))

from matrix_client import EDID_PRESETS, MatrixClient, MatrixError  # noqa: E402

REAL_VIDEO_RESPONSE = (
    'VideoCallback({"o1":"2",            "o2":"2",            "s1":"1",            '
    '"s2":"1",            "group":"0",            "account":"admin",            '
    '"ip":"192.168.17.238",            "port":"001011",            "in1":"Windows",'
    '\t\t\t      "in2":"MacBook",\t\t\t      "in3":"AppleTv",\t\t\t      "in4":"MacMini",'
    '\t\t\t      "out1":"Left",\t\t\t      "out2":"Right",\t\t\t      "ver":"V0.0.11",            });'
)
REAL_AUDIO_RESPONSE = 'AudioCallback({"arc":"0",            "ext":"1",            });'


def make_client() -> MatrixClient:
    return MatrixClient("matrix.test", "admin", "admin")


class TestJsonpParsing(unittest.TestCase):
    def test_parses_real_video_response(self):
        data = make_client()._parse_jsonp(REAL_VIDEO_RESPONSE, "VideoCallback")
        self.assertEqual(data["in3"], "AppleTv")

    def test_rejects_garbage(self):
        with self.assertRaises(MatrixError):
            make_client()._parse_jsonp("nope", "VideoCallback")


class TestGetState(unittest.TestCase):
    def test_aggregates_for_ha_entities(self):
        client = make_client()
        client._logged_in = True
        with patch.object(client, "_request") as mock_req:
            mock_req.side_effect = [REAL_VIDEO_RESPONSE, REAL_AUDIO_RESPONSE,
                                     'EdidCallback({"i1":"0","i2":"0","i3":"0","i4":"0",});']
            state = client.get_state()
        # This is exactly the shape select.py / switch.py / sensor.py index into.
        self.assertEqual({o["index"] for o in state["outputs"]}, {1, 2})
        self.assertEqual({i["index"] for i in state["inputs"]}, {1, 2, 3, 4})
        self.assertEqual(len(state["edid_presets"]), len(EDID_PRESETS))


class TestCommandValidation(unittest.TestCase):
    def test_set_route_validates_before_any_network_call(self):
        client = make_client()
        with patch.object(client, "_request") as mock_req:
            with self.assertRaises(MatrixError):
                client.set_route(output=1, input_=99)
        mock_req.assert_not_called()


class TestInputValidation(unittest.TestCase):
    """Values are spliced into space-separated `#cmd key=value` strings, so
    anything that could smuggle extra keys or commands must be refused
    before a request is made (#41)."""

    def setUp(self):
        self.client = make_client()
        self.client._logged_in = True

    def assert_rejected(self, call):
        with patch.object(self.client, "_request") as req:
            with self.assertRaises(MatrixError):
                call()
            req.assert_not_called()

    def test_set_network_rejects_command_injection(self):
        self.assert_rejected(lambda: self.client.set_network(
            "1.2.3.4 gw=0.0.0.0 #factory0", "255.255.255.0", "1.2.3.1"))

    def test_set_network_rejects_injection_in_mask_and_gateway(self):
        self.assert_rejected(lambda: self.client.set_network("192.168.1.10", "255.255.255.0 #x", "192.168.1.1"))
        self.assert_rejected(lambda: self.client.set_network("192.168.1.10", "255.255.255.0", "1.1.1.1#x"))

    def test_set_network_rejects_out_of_range_octet(self):
        self.assert_rejected(lambda: self.client.set_network("192.168.1.300", "255.255.255.0", "192.168.1.1"))

    def test_set_network_rejects_non_contiguous_mask(self):
        self.assert_rejected(lambda: self.client.set_network("192.168.1.10", "255.0.255.0", "192.168.1.1"))

    def test_set_network_sends_normalized_values(self):
        with patch.object(self.client, "_request") as req:
            self.client.set_network(" 192.168.1.10 ", "255.255.255.0", "192.168.1.1")
        req.assert_called_once_with("POST", "ip.set", "#ip ip=192.168.1.10 mask=255.255.255.0 gw=192.168.1.1")

    def test_rename_rejects_out_of_range_index(self):
        self.assert_rejected(lambda: self.client.rename_port("in", 5, "Valid_Name"))
        self.assert_rejected(lambda: self.client.rename_port("out", 3, "Valid_Name"))
        self.assert_rejected(lambda: self.client.rename_port("in", 0, "Valid_Name"))

    def test_rename_rejects_non_int_index(self):
        self.assert_rejected(lambda: self.client.rename_port("in", "1 name=x", "Valid_Name"))
        self.assert_rejected(lambda: self.client.rename_port("in", True, "Valid_Name"))

    def test_rename_accepts_valid_index(self):
        with patch.object(self.client, "_request") as req:
            self.client.rename_port("out", 2, "Right_TV")
        req.assert_called_once_with("POST", "video_set", "#port out2 name=Right_TV")

    def test_set_password_rejects_unknown_group(self):
        self.assert_rejected(lambda: self.client.set_password("admin1", "secret1", group="0 #factory0"))
        self.assert_rejected(lambda: self.client.set_password("admin1", "secret1", group="1"))


if __name__ == "__main__":
    unittest.main()
