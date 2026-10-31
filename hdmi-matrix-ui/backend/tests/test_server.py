"""End-to-end test of server.py: runs the real stdlib HTTP server, backed
by the in-memory mock matrix client, in a background thread and drives it
over actual HTTP with urllib -- no mocking the HTTP layer itself, no
network/hardware dependency."""

from __future__ import annotations

import http.client
import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent))

# Must be set before `server` (and therefore `config`) is imported, since
# the client is constructed at module import time.
os.environ["MATRIX_HOST"] = "mock"

from http.server import ThreadingHTTPServer  # noqa: E402

import server as server_module  # noqa: E402


class ServerTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server_module.Handler)
        cls.base_url = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    def setUp(self):
        server_module.state_cache.invalidate()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join(timeout=5)

    def _get(self, path):
        with urllib.request.urlopen(f"{self.base_url}{path}", timeout=5) as resp:
            return resp.status, json.loads(resp.read())

    def _post(self, path, payload):
        data = json.dumps(payload).encode()
        req = urllib.request.Request(f"{self.base_url}{path}", data=data, method="POST",
                                      headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read())

    def test_homepage_serves_frontend(self):
        with urllib.request.urlopen(f"{self.base_url}/", timeout=5) as resp:
            self.assertEqual(resp.status, 200)
            body = resp.read().decode()
        self.assertIn("<title>HDMI Matrix</title>", body)

    def test_static_asset_served_with_content_type(self):
        with urllib.request.urlopen(f"{self.base_url}/styles.css", timeout=5) as resp:
            self.assertEqual(resp.status, 200)
            self.assertIn("text/css", resp.headers.get("Content-Type", ""))

    def test_path_traversal_is_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(f"{self.base_url}/../server.py", timeout=5)
        self.assertEqual(ctx.exception.code, 404)

    def test_api_state_shape(self):
        status, body = self._get("/api/state")
        self.assertEqual(status, 200)
        self.assertEqual(len(body["inputs"]), 4)
        self.assertEqual(len(body["outputs"]), 2)
        self.assertIn("audio", body)
        self.assertIn("edid_presets", body)

    def test_route_command_updates_state(self):
        status, body = self._post("/api/route", {"output": 1, "input": 2})
        self.assertEqual(status, 200)
        left = next(o for o in body["outputs"] if o["index"] == 1)
        self.assertEqual(left["input_index"], 2)

    def test_route_command_rejects_invalid_output(self):
        # MatrixClient.set_route validates and raises MatrixError, which the
        # server maps to 502 (same bucket as a real device-side rejection).
        status, body = self._post("/api/route", {"output": 9, "input": 1})
        self.assertEqual(status, 502)
        self.assertIn("error", body)

    def test_output_power_toggle(self):
        status, body = self._post("/api/output-power", {"output": 2, "on": False})
        self.assertEqual(status, 200)
        right = next(o for o in body["outputs"] if o["index"] == 2)
        self.assertFalse(right["power"])
        # restore for other tests
        self._post("/api/output-power", {"output": 2, "on": True})

    def test_reboot_returns_success_without_followup_state_poll(self):
        with patch.object(server_module.client, "reboot") as reboot, patch.object(
            server_module.state_cache,
            "get",
            side_effect=server_module.MatrixError("offline"),
        ) as get_state:
            status, body = self._post("/api/system/reboot", {})

        self.assertEqual(status, 200)
        self.assertEqual(body, {"ok": True})
        reboot.assert_called_once_with()
        get_state.assert_not_called()

    def test_factory_reset_returns_success_without_followup_state_poll(self):
        with patch.object(server_module.client, "factory_reset") as factory_reset, patch.object(
            server_module.state_cache,
            "get",
            side_effect=server_module.MatrixError("offline"),
        ) as get_state:
            status, body = self._post("/api/system/factory-reset", {})

        self.assertEqual(status, 200)
        self.assertEqual(body, {"ok": True})
        factory_reset.assert_called_once_with()
        get_state.assert_not_called()

    def test_rename_rejects_invalid_name(self):
        status, body = self._post("/api/rename", {"kind": "in", "index": 1, "name": "x"})
        self.assertEqual(status, 502)  # MatrixError from rename_port's validation
        self.assertIn("error", body)

    # -- CSRF guard (#40) ------------------------------------------------

    def _raw_post(self, path, body=b"{}", headers=None):
        req = urllib.request.Request(f"{self.base_url}{path}", data=body, method="POST",
                                     headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status
        except urllib.error.HTTPError as exc:
            return exc.code

    def test_text_plain_post_is_rejected(self):
        # What a hostile page's fetch(..., {mode: 'no-cors'}) sends.
        status = self._raw_post("/api/system/factory-reset", headers={"Content-Type": "text/plain"})
        self.assertEqual(status, 415)

    def test_post_without_content_type_is_rejected(self):
        status = self._raw_post("/api/system/reboot", headers={"Content-Type": ""})
        self.assertEqual(status, 415)

    def test_cross_origin_post_is_rejected(self):
        status = self._raw_post("/api/system/factory-reset", headers={
            "Content-Type": "application/json", "Origin": "https://evil.example"})
        self.assertEqual(status, 403)

    def test_rebinding_origin_with_different_port_is_rejected(self):
        host = self.base_url.removeprefix("http://").split(":")[0]
        status = self._raw_post("/api/system/reboot", headers={
            "Content-Type": "application/json", "Origin": f"http://{host}:1"})
        self.assertEqual(status, 403)

    def test_same_origin_post_is_allowed(self):
        host = self.base_url.removeprefix("http://")
        status = self._raw_post("/api/route", json.dumps({"output": 1, "input": 1}).encode(), headers={
            "Content-Type": "application/json; charset=utf-8", "Origin": f"http://{host}"})
        self.assertEqual(status, 200)

    def test_rejected_post_never_reaches_the_matrix(self):
        with patch.object(server_module.client, "factory_reset") as reset:
            self._raw_post("/api/system/factory-reset", headers={"Content-Type": "text/plain"})
            self._raw_post("/api/system/factory-reset", headers={
                "Content-Type": "application/json", "Origin": "https://evil.example"})
        reset.assert_not_called()

    def test_api_token_required_when_configured(self):
        with patch.dict(server_module.config, {"api_token": "s3cret"}):
            self.assertEqual(self._raw_post("/api/route", json.dumps({"output": 1, "input": 1}).encode(),
                                            headers={"Content-Type": "application/json"}), 401)
            self.assertEqual(self._raw_post("/api/route", json.dumps({"output": 1, "input": 1}).encode(),
                                            headers={"Content-Type": "application/json",
                                                     "X-API-Token": "wrong"}), 401)
            self.assertEqual(self._raw_post("/api/route", json.dumps({"output": 1, "input": 1}).encode(),
                                            headers={"Content-Type": "application/json",
                                                     "X-API-Token": "s3cret"}), 200)
            # Reading state stays open.
            status, _ = self._get("/api/state")
            self.assertEqual(status, 200)

    def test_network_rejects_command_injection(self):
        status, body = self._post("/api/network", {"ip": "1.2.3.4 gw=0.0.0.0 #factory0",
                                                   "mask": "255.255.255.0", "gw": "1.2.3.1"})
        self.assertEqual(status, 502)  # MatrixError, same bucket as other validation failures
        self.assertIn("IPv4", body["error"])

    def test_rename_rejects_out_of_range_index(self):
        status, body = self._post("/api/rename", {"kind": "out", "index": 3, "name": "Valid_Name"})
        self.assertEqual(status, 502)
        self.assertIn("index", body["error"])

    def test_unknown_route_is_404(self):
        status, body = self._post("/api/does-not-exist", {})
        self.assertEqual(status, 404)

    # -- request body validation (#45) ---------------------------------

    def _post_with_content_length(self, value, body=b"{}"):
        host, port = self.httpd.server_address
        conn = http.client.HTTPConnection(host, port, timeout=5)
        conn.putrequest("POST", "/api/route")
        conn.putheader("Content-Type", "application/json")
        conn.putheader("Content-Length", value)
        conn.endheaders(body)
        response = conn.getresponse()
        payload = json.loads(response.read())
        conn.close()
        return response.status, payload

    def test_bad_content_length_returns_400(self):
        status, body = self._post_with_content_length("abc")
        self.assertEqual(status, 400)
        self.assertIn("Invalid Content-Length", body["error"])

    def test_negative_and_oversized_content_length_return_400(self):
        for value in ("-1", str(server_module.MAX_BODY_BYTES + 1)):
            status, body = self._post_with_content_length(value)
            self.assertEqual(status, 400)
            self.assertIn("body", body["error"])

    def test_invalid_utf8_and_non_object_json_return_400(self):
        status = self._raw_post(
            "/api/route", b"\xff", headers={"Content-Type": "application/json"}
        )
        self.assertEqual(status, 400)
        status, body = self._post("/api/route", [1, 2])
        self.assertEqual(status, 400)
        self.assertIn("JSON body must be an object", body["error"])

    def test_state_cache_coalesces_reads_and_invalidates(self):
        class CountingClient:
            def __init__(self):
                self.reads = 0

            def get_state(self):
                self.reads += 1
                return {"reads": self.reads}

        client = CountingClient()
        cache = server_module.StateCache(client, ttl=10)
        for _ in range(20):
            cache.get()
        self.assertEqual(client.reads, 1)
        cache.invalidate()
        self.assertEqual(cache.get(), {"reads": 2})


class TestStartupHelpers(unittest.TestCase):
    def test_detect_lan_ip_returns_none_on_socket_error(self):
        with patch("socket.socket.connect", side_effect=OSError("no route")):
            self.assertIsNone(server_module.detect_lan_ip())

    def test_detect_lan_ip_ignores_loopback(self):
        with patch("socket.socket.getsockname", return_value=("127.0.0.1", 0)):
            self.assertIsNone(server_module.detect_lan_ip())


if __name__ == "__main__":
    unittest.main()
