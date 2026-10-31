from __future__ import annotations

import ipaddress
import json
import os
import re
from pathlib import Path

BACKEND_DIR = Path(__file__).parent
CONFIG_PATH = BACKEND_DIR / "config.json"

DEFAULTS = {
    "matrix_host": "matrix.local",
    "matrix_username": "admin",
    "matrix_password": "admin",
    "listen_host": "0.0.0.0",
    "listen_port": 8765,
    # Optional shared secret for state-changing requests (sent as the
    # X-API-Token header). Empty disables it.
    "api_token": "",
    "trusted_hosts": [],
}


def parse_trusted_hosts(value: str | list[str] | None) -> list[str]:
    """Return exact normalized hostname entries for the request host allowlist."""
    if value is None:
        entries = []
    elif isinstance(value, str):
        entries = value.split(",")
    elif isinstance(value, list):
        entries = value
    else:
        raise ValueError("trusted_hosts must be a comma-separated string or list of hostnames")

    hosts = []
    for entry in entries:
        if not isinstance(entry, str):
            raise ValueError("trusted_hosts entries must be hostnames")
        hostname = entry.strip().rstrip(".")
        if not hostname:
            continue
        try:
            ipaddress.ip_address(hostname)
        except ValueError:
            pass
        else:
            raise ValueError("trusted_hosts entries must be hostnames, not IP addresses")
        try:
            hostname = hostname.encode("idna").decode("ascii").lower()
        except UnicodeError as exc:
            raise ValueError(f"invalid trusted hostname: {entry}") from exc
        if len(hostname) > 253 or any(
            not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
            for label in hostname.split(".")
        ):
            raise ValueError(f"invalid trusted hostname: {entry}")
        hosts.append(hostname)
    return list(dict.fromkeys(hosts))


def load_config() -> dict:
    config = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        config.update(json.loads(CONFIG_PATH.read_text()))
    # Environment variables take precedence over config.json, for quick overrides.
    env_map = {
        "MATRIX_HOST": "matrix_host",
        "MATRIX_USERNAME": "matrix_username",
        "MATRIX_PASSWORD": "matrix_password",
        "LISTEN_HOST": "listen_host",
        "LISTEN_PORT": "listen_port",
        "API_TOKEN": "api_token",
    }
    for env_key, cfg_key in env_map.items():
        if env_key in os.environ:
            value = os.environ[env_key]
            config[cfg_key] = int(value) if cfg_key == "listen_port" else value
    if "TRUSTED_HOSTS" in os.environ:
        config["trusted_hosts"] = os.environ["TRUSTED_HOSTS"]
    config["trusted_hosts"] = parse_trusted_hosts(config.get("trusted_hosts"))
    return config
