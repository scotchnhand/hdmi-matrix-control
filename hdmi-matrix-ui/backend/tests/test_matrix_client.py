"""Unit tests for matrix_client.py.

These never touch the network -- MatrixClient._request is patched out so
the tests exercise the actual reverse-engineered parsing/validation logic
against known-real response strings (captured from the device) instead.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent))

from matrix_client import EDID_PRESETS, MatrixAuthError, MatrixClient, MatrixError  # noqa: E402

# Real responses captured from the device while reverse-engineering the
# protocol -- see docs/PROTOCOL.md. Deliberately kept verbatim, trailing
# comma and all, since that's exactly what the parser has to handle.
REAL_VIDEO_RESPONSE = (
    'VideoCallback({"o1":"2",            "o2":"2",            "s1":"1",            '
    '"s2":"1",            "group":"0",            "account":"admin",            '
    '"ip":"192.168.17.238",            "port":"001011",            "in1":"Windows",'
    '\t\t\t      "in2":"MacBook",\t\t\t      "in3":"AppleTv",\t\t\t      "in4":"MacMini",'
    '\t\t\t      "out1":"Left",\t\t\t      "out2":"Right",\t\t\t      "ver":"V0.0.11",            });'
)
REAL_AUDIO_RESPONSE = 'AudioCallback({"arc":"0",            "ext":"1",            });'
REAL_EDID_RESPONSE = (
    'EdidCallback({"i1":"15",            "i2":"1",            "i3":"2",            "i4":"15",            '
    '"e1":"1920x1080P@60 LPCM:2.0",            "e2":"1920x1200P@60 LPCM:2.0",            '
    '"e3":"1920x1080P@60 LPCM:2.0",            "port":"001011",            });'
)
REAL_LOGIN_OK = 'settingsLoginCallback({"status":"0","str":"",});'
REAL_LOGIN_FAIL = 'settingsLoginCallback({"status":"6","str":"Invalid user or password",});'


def make_client() -> MatrixClient:
    return MatrixClient("matrix.test", "admin", "admin")


class TestJsonpParsing(unittest.TestCase):
    def test_parses_real_video_response(self):
        client = make_client()
        data = client._parse_jsonp(REAL_VIDEO_RESPONSE, "VideoCallback")
        self.assertEqual(data["o1"], "2")
        self.assertEqual(data["in3"], "AppleTv")
        self.assertEqual(data["ver"], "V0.0.11")

    def test_parses_real_audio_response(self):
        client = make_client()
        data = client._parse_jsonp(REAL_AUDIO_RESPONSE, "AudioCallback")
        self.assertEqual(data, {"arc": "0", "ext": "1"})

    def test_parses_real_edid_response(self):
        client = make_client()
        data = client._parse_jsonp(REAL_EDID_RESPONSE, "EdidCallback")
        self.assertEqual(data["i1"], "15")
        self.assertEqual(data["e2"], "1920x1200P@60 LPCM:2.0")

    def test_rejects_wrong_callback_name(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client._parse_jsonp(REAL_VIDEO_RESPONSE, "WrongCallback")

    def test_rejects_garbage(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client._parse_jsonp("<html>not json</html>", "VideoCallback")

    def test_handles_response_without_trailing_whitespace(self):
        client = make_client()
        data = client._parse_jsonp('AudioCallback({"arc":"1","ext":"2"});', "AudioCallback")
        self.assertEqual(data, {"arc": "1", "ext": "2"})


class TestLogin(unittest.TestCase):
    def test_login_success_sets_flag(self):
        client = make_client()
        with patch.object(client, "_request", return_value=REAL_LOGIN_OK) as mock_req:
            client.login()
        self.assertTrue(client._logged_in)
        # body should carry base64("admin") for both id and psd
        body = mock_req.call_args.args[2]
        self.assertIn("id=YWRtaW4=", body)
        self.assertIn("psd=YWRtaW4=", body)

    def test_login_failure_raises_and_does_not_set_flag(self):
        client = make_client()
        with patch.object(client, "_request", return_value=REAL_LOGIN_FAIL):
            with self.assertRaises(MatrixError) as ctx:
                client.login()
        self.assertIn("Invalid user or password", str(ctx.exception))
        self.assertFalse(client._logged_in)

    def test_login_rejection_is_an_auth_error_not_a_transport_error(self):
        client = make_client()
        with patch.object(client, "_request", return_value=REAL_LOGIN_FAIL):
            with self.assertRaises(MatrixAuthError):
                client.login()
        with patch.object(client, "_request", side_effect=MatrixError("unreachable")):
            with self.assertRaises(MatrixError) as ctx:
                client.login()
        self.assertNotIsInstance(ctx.exception, MatrixAuthError)


class TestTransportErrors(unittest.TestCase):
    def test_read_timeout_becomes_matrix_error(self):
        # A locked-up matrix accepts the connection then never answers, which
        # urlopen surfaces as a bare TimeoutError rather than a URLError.
        client = make_client()
        with patch("urllib.request.urlopen", side_effect=TimeoutError("timed out")):
            with self.assertRaises(MatrixError):
                client._request("GET", "video.get")


class TestGetState(unittest.TestCase):
    def test_aggregates_and_normalizes(self):
        client = make_client()
        client._logged_in = True  # skip login for this test
        with patch.object(client, "_request") as mock_req:
            mock_req.side_effect = [REAL_VIDEO_RESPONSE, REAL_AUDIO_RESPONSE, REAL_EDID_RESPONSE]
            state = client.get_state()

        # o1 = "2" (0-indexed) -> input_index 3 (AppleTv)
        left = next(o for o in state["outputs"] if o["name"] == "Left")
        self.assertEqual(left["input_index"], 3)
        self.assertTrue(left["power"])

        self.assertEqual(state["inputs"][2]["name"], "AppleTv")
        self.assertEqual(state["audio"]["arc"]["label"], "Off")
        self.assertEqual(state["audio"]["extraction"]["label"], "Out-A")
        self.assertEqual(state["device"]["ip"], "192.168.17.238")
        self.assertEqual(len(state["edid_presets"]), len(EDID_PRESETS))

    def test_malformed_response_relogs_and_retries_once(self):
        client = make_client()
        client._logged_in = True
        responses = iter(["<html>login</html>", REAL_LOGIN_OK, REAL_VIDEO_RESPONSE])
        with patch.object(client, "_request", side_effect=lambda *args: next(responses)) as request:
            video = client.get_video()

        self.assertEqual(video["in1"], "Windows")
        self.assertEqual(request.call_count, 3)

    def test_second_malformed_response_raises_without_looping(self):
        client = make_client()
        client._logged_in = True
        responses = iter(["junk", REAL_LOGIN_OK, "junk"])
        with patch.object(client, "_request", side_effect=lambda *args: next(responses)) as request:
            with self.assertRaises(MatrixError):
                client.get_video()

        self.assertEqual(request.call_count, 3)

    def test_transport_error_does_not_trigger_relogin(self):
        client = make_client()
        client._logged_in = True
        with patch.object(client, "_request", side_effect=MatrixError("unreachable")) as request:
            with self.assertRaises(MatrixError):
                client.get_video()

        request.assert_called_once_with("GET", "video.get")


class TestCommandValidation(unittest.TestCase):
    """Every public setter validates before touching the network, so these
    never need to patch _request -- an invalid call must never reach it."""

    def test_set_route_rejects_bad_output(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client.set_route(output=3, input_=1)

    def test_set_route_rejects_bad_input(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client.set_route(output=1, input_=5)

    def test_set_route_sends_zero_indexed_input(self):
        client = make_client()
        client._logged_in = True
        with patch.object(client, "_request") as mock_req:
            client.set_route(output=1, input_=3)
        mock_req.assert_called_once_with("POST", "video_set", "#video_d out1 matrix=2")

    def test_rename_port_rejects_short_name(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client.rename_port("in", 1, "ab")

    def test_rename_port_rejects_symbols(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client.rename_port("in", 1, "bad name!")

    def test_rename_port_accepts_valid_name(self):
        client = make_client()
        client._logged_in = True
        with patch.object(client, "_request") as mock_req:
            client.rename_port("out", 2, "Bedroom_TV")
        mock_req.assert_called_once_with("POST", "video_set", "#port out2 name=Bedroom_TV")

    def test_set_edid_rejects_out_of_range_preset(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client.set_edid(1, len(EDID_PRESETS))

    def test_set_audio_rejects_bad_mode(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client.set_audio("bogus", 1)

    def test_set_audio_extraction_maps_to_dec_wire_command(self):
        client = make_client()
        client._logged_in = True
        with patch.object(client, "_request") as mock_req:
            client.set_audio("extraction", 2)
        mock_req.assert_called_once_with("POST", "audio_set", "#audio_d dec=2")

    def test_set_password_rejects_short_credentials(self):
        client = make_client()
        with self.assertRaises(MatrixError):
            client.set_password("ab", "longenoughpassword")


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
