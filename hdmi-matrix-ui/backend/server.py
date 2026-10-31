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

import hmac
import ipaddress
import json
import mimetypes
import os
import re
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, urlsplit

from config import load_config
from matrix_client import MatrixClient, MatrixError
from version import __version__

FRONTEND_DIR = (Path(__file__).parent.parent / "frontend").resolve()
MAX_BODY_BYTES = 16 * 1024
BUILD_CHANNEL = os.environ.get("APP_BUILD_CHANNEL") or "stable"
BUILD_REVISION = os.environ.get("APP_BUILD_REVISION") or "local"
TRUSTED_IPV4_NETWORKS = tuple(
    ipaddress.ip_network(network) for network in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)
TRUSTED_IPV6_NETWORK = ipaddress.ip_network("fc00::/7")

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


class StateCache:
    """Coalesce state reads from all browser tabs in this backend process."""

    def __init__(self, matrix_client, ttl: float = 2.5):
        self._client = matrix_client
        self._ttl = ttl
        self._lock = threading.Lock()
        self._value = None
        self._at = 0.0

    def get(self):
        with self._lock:
            if self._value is None or time.monotonic() - self._at > self._ttl:
                self._value = self._client.get_state()
                self._at = time.monotonic()
            return self._value

    def invalidate(self):
        with self._lock:
            self._value = None


state_cache = StateCache(client)


def json_body(handler: BaseHTTPRequestHandler) -> dict:
    raw_length = handler.headers.get("Content-Length", "0")
    try:
        length = int(raw_length)
    except ValueError as exc:
        raise MatrixError("Invalid Content-Length") from exc
    if length < 0 or length > MAX_BODY_BYTES:
        raise MatrixError("Request body too large or invalid length")
    if length == 0:
        return {}
    raw = handler.rfile.read(length)
    try:
        body = json.loads(raw.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise MatrixError(f"Invalid JSON body: {exc}") from exc
    if not isinstance(body, dict):
        raise MatrixError("JSON body must be an object")
    return body


def _is_json(handler: BaseHTTPRequestHandler) -> bool:
    ctype = handler.headers.get("Content-Type", "")
    return ctype.split(";", 1)[0].strip().lower() == "application/json"


def _origin_allowed(handler: BaseHTTPRequestHandler) -> bool:
    """Allow same-origin control requests only for local IPs or trusted names.

    Requests without an Origin header (curl, scripts, Home Assistant) are
    allowed: browsers always send Origin on cross-origin POSTs, so its
    absence means the request didn't come from a hostile web page. Hostnames
    are exact allowlist entries to prevent DNS rebinding.
    """
    origins = handler.headers.get_all("Origin", [])
    if not origins:
        return True
    if len(origins) != 1:
        return False
    origin = origins[0]
    hosts = handler.headers.get_all("Host", [])
    if len(hosts) != 1:
        return False
    host_header = hosts[0]
    if not origin or not host_header or any(char.isspace() for char in origin + host_header):
        return False

    try:
        origin_parts = urlsplit(origin)
        if (
            origin_parts.scheme.lower() not in ("http", "https")
            or not origin_parts.netloc
            or origin_parts.netloc.endswith(":")
            or origin_parts.username is not None
            or origin_parts.password is not None
            or origin_parts.path
            or origin_parts.query
            or origin_parts.fragment
        ):
            return False
        origin_hostname = origin_parts.hostname
        origin_port = origin_parts.port

        host_parts = urlsplit(f"//{host_header}")
        if (
            not host_parts.netloc
            or host_parts.netloc.endswith(":")
            or host_parts.username is not None
            or host_parts.password is not None
            or host_parts.path
            or host_parts.query
            or host_parts.fragment
        ):
            return False
        host_name = host_parts.hostname
        host_port = host_parts.port
    except ValueError:
        return False

    origin_name = _normalize_request_host(origin_hostname)
    request_name = _normalize_request_host(host_name)
    if origin_name is None or request_name is None or origin_name[0] != request_name[0]:
        return False

    default_port = 443 if origin_parts.scheme.lower() == "https" else 80
    origin_effective_port = default_port if origin_port is None else origin_port
    host_effective_port = default_port if host_port is None else host_port
    if origin_effective_port != host_effective_port:
        return False

    address = origin_name[1]
    if address is not None:
        if address.is_loopback:
            return True
        if address.version == 4:
            return any(address in network for network in TRUSTED_IPV4_NETWORKS)
        return address in TRUSTED_IPV6_NETWORK

    return origin_name[0] in config.get("trusted_hosts", [])


def _normalize_request_host(
    hostname: str | None,
) -> tuple[str, ipaddress.IPv4Address | ipaddress.IPv6Address | None] | None:
    if not hostname or "%" in hostname:
        return None
    try:
        address = ipaddress.ip_address(hostname)
        return address.compressed.lower(), address
    except ValueError:
        pass
    try:
        normalized = hostname.rstrip(".").encode("idna").decode("ascii").lower()
    except UnicodeError:
        return None
    if len(normalized) > 253 or any(
        not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
        for label in normalized.split(".")
    ):
        return None
    return normalized, None


def _token_ok(handler: BaseHTTPRequestHandler) -> bool:
    token = config.get("api_token") or ""
    if not token:
        return True
    supplied = handler.headers.get("X-API-Token", "")
    return hmac.compare_digest(supplied.encode("utf-8"), token.encode("utf-8"))


def csrf_rejection(handler: BaseHTTPRequestHandler) -> tuple[int, str] | None:
    """Return (status, message) if a state-changing request must be refused.

    Requiring application/json makes every POST "non-simple", so a browser
    must send a CORS preflight first -- which this server never answers --
    and a hostile page can't fire commands at the matrix. The Origin check
    also covers DNS-rebinding and any browser that skips preflight.
    """
    if not _is_json(handler):
        return 415, "Content-Type must be application/json"
    if not _origin_allowed(handler):
        return 403, "Cross-origin request rejected"
    if not _token_ok(handler):
        return 401, "Missing or invalid API token"
    return None


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
        if path == "/api/version":
            self._send_json({
                "version": __version__,
                "channel": BUILD_CHANNEL,
                "revision": BUILD_REVISION,
            })
            return
        if path == "/api/state":
            self._handle(state_cache.get)
            return
        self._serve_static(path)

    def do_POST(self):
        path = urlparse(self.path).path
        rejection = csrf_rejection(self)
        if rejection is not None:
            status, message = rejection
            self._send_json({"error": message}, status=status)
            return
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
            state_cache.invalidate()
            if path in ("/api/system/reboot", "/api/system/factory-reset"):
                return {"ok": True}
            if path == "/api/network":
                return {"ok": True, "settings_changed": "network"}
            if path == "/api/system/password":
                return {"ok": True, "settings_changed": "password"}
            return state_cache.get()

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


def detect_lan_ip() -> str | None:
    """Best-effort outbound interface IP for the startup help text."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            # UDP connect selects a route; it does not send a packet.
            sock.connect(("10.255.255.255", 1))
            ip = sock.getsockname()[0]
            return None if ip.startswith("127.") else ip
    except OSError:
        return None


def main():
    host = config["listen_host"]
    port = config["listen_port"]
    httpd = ThreadingHTTPServer((host, port), Handler)

    print(f"HDMI Matrix UI {__version__} serving on:")
    print(f"  http://localhost:{port}")
    lan_ip = detect_lan_ip()
    if lan_ip:
        print(f"  http://{lan_ip}:{port}  (use this from your phone/tablet on the same network)")
    else:
        print("  (could not detect LAN IP -- use this machine's address on your network)")
    if os.path.exists("/.dockerenv"):
        print("  Running in Docker: use the HOST's IP and the published port.")
    print(f"Proxying to matrix at http://{config['matrix_host']}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
