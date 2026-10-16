"""End-to-end test of server.py: runs the real stdlib HTTP server, backed
by the in-memory mock matrix client, in a background thread and drives it
over actual HTTP with urllib -- no mocking the HTTP layer itself, no
network/hardware dependency."""

from __future__ import annotations

import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

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

    def test_rename_rejects_invalid_name(self):
        status, body = self._post("/api/rename", {"kind": "in", "index": 1, "name": "x"})
        self.assertEqual(status, 502)  # MatrixError from rename_port's validation
        self.assertIn("error", body)

    def test_unknown_route_is_404(self):
        status, body = self._post("/api/does-not-exist", {})
        self.assertEqual(status, 404)


if __name__ == "__main__":
    unittest.main()
