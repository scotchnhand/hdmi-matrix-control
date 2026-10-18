from __future__ import annotations

import json
import os
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
}


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
    return config
