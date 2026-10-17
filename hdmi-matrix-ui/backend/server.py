#!/usr/bin/env python3
"""Local proxy + static server for the HDMI matrix UI.

Zero third-party dependencies on purpose -- `python3 server.py` is the
entire setup. It serves the frontend/ folder as static files and
exposes a small JSON API under /api/* that the frontend calls, which
this process translates into the matrix's own undocumented protocol
(see matrix_client.py).

Why a server at all instead of a static page hitting the matrix
directly: the matrix sends no CORS headers, so a browser would block
cross-origin fetches to it from anything not served by the matrix
itself. Running this on the same machine (or any machine on the LAN)
and browsing to it from phones/tablets/laptops sidesteps that.
"""

from __future__ import annotations

import json
import mimetypes
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from config import load_config
from matrix_client import MatrixClient, MatrixError

FRONTEND_DIR = (Path(__file__).parent.parent / "frontend").resolve()

config = load_config()
if config["matrix_host"] == "mock":
    from mock_client import MockMatrixClient
    client = MockMatrixClient()
else:
    client = MatrixClient(
        host=config["matrix_host"],
        username=config["matrix_username"],
        password=config["matrix_password"],
    )


def json_body(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", 0))
    if length == 0:
        return {}
    raw = handler.rfile.read(length)
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise MatrixError(f"Invalid JSON body: {exc}") from exc


class Handler(BaseHTTPRequestHandler):
    server_version = "HdmiMatrixUI/1.0"

    # -- helpers ---------------------------------------------------------

    def _send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, exc: Exception, status=502):
        self._send_json({"error": str(exc)}, status=status)

    def _serve_static(self, path: str):
        if path == "/":
            path = "/index.html"
        safe_path = Path(path.lstrip("/"))
        if ".." in safe_path.parts:
            self._send_json({"error": "Not found"}, status=404)
            return
        full_path = (FRONTEND_DIR / safe_path).resolve()
        if FRONTEND_DIR not in full_path.parents and full_path != FRONTEND_DIR:
            self._send_json({"error": "Not found"}, status=404)
            return
        if not full_path.is_file():
            self._send_json({"error": "Not found"}, status=404)
            return
        content_type, _ = mimetypes.guess_type(str(full_path))
        data = full_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        if full_path.suffix == ".html":
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    # -- routing -----------------------------------------------------------

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/healthz":
            self._send_json({"status": "ok", "service": "hdmi-matrix-ui"})
            return
        if path == "/api/state":
            self._handle(lambda: client.get_state())
            return
        self._serve_static(path)

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            body = json_body(self)
        except MatrixError as exc:
            self._send_error_json(exc, status=400)
            return

        routes = {
            "/api/route": lambda: client.set_route(int(body["output"]), int(body["input"])),
            "/api/output-power": lambda: client.set_output_power(int(body["output"]), bool(body["on"])),
            "/api/rename": lambda: client.rename_port(body["kind"], int(body["index"]), body["name"]),
            "/api/edid": lambda: client.set_edid(int(body["input"]), int(body["preset"])),
            "/api/audio": lambda: client.set_audio(body["mode"], int(body["value"])),
            "/api/system/reboot": client.reboot,
            "/api/system/factory-reset": client.factory_reset,
            "/api/network": lambda: client.set_network(body["ip"], body["mask"], body["gw"]),
            "/api/system/password": lambda: client.set_password(body["user"], body["password"]),
        }

        action = routes.get(path)
        if action is None:
            self._send_json({"error": "Not found"}, status=404)
            return

        def run():
            action()
            return client.get_state()

        self._handle(run)

    def _handle(self, fn):
        try:
            result = fn()
            self._send_json(result if result is not None else {"ok": True})
        except MatrixError as exc:
            self._send_error_json(exc, status=502)
        except (KeyError, ValueError, TypeError) as exc:
            self._send_error_json(exc, status=400)
        except Exception as exc:  # noqa: BLE001 - surface unexpected errors to the UI instead of a blank 500
            self._send_error_json(exc, status=500)

    def log_message(self, format, *args):  # noqa: A002 - matches BaseHTTPRequestHandler signature
        print(f"[hdmi-matrix-ui] {self.address_string()} - {format % args}")


def main():
    host = config["listen_host"]
    port = config["listen_port"]
    httpd = ThreadingHTTPServer((host, port), Handler)

    lan_ip = socket.gethostbyname(socket.gethostname())
    print("HDMI Matrix UI serving on:")
    print(f"  http://localhost:{port}")
    print(f"  http://{lan_ip}:{port}  (use this from your phone/tablet on the same network)")
    print(f"Proxying to matrix at http://{config['matrix_host']}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
