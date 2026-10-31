from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent))

import config as config_module  # noqa: E402


class TrustedHostsConfigTests(unittest.TestCase):
    def test_trusted_hosts_parses_comma_separated_names_and_ignores_empty_entries(self):
        self.assertEqual(
            config_module.parse_trusted_hosts(" , EXAMPLE.COM., matrix.local, ,"),
            ["example.com", "matrix.local"],
        )

    def test_trusted_hosts_accepts_json_hostname_list(self):
        self.assertEqual(config_module.parse_trusted_hosts(["Router.Home", ""]), ["router.home"])

    def test_trusted_hosts_environment_overrides_json_config(self):
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.json"
            config_path.write_text(json.dumps({"trusted_hosts": ["file.local"]}))
            with patch.object(config_module, "CONFIG_PATH", config_path), patch.dict(
                os.environ, {"TRUSTED_HOSTS": "env.local, another.local"}, clear=True
            ):
                self.assertEqual(config_module.load_config()["trusted_hosts"], ["env.local", "another.local"])

    def test_trusted_hosts_loads_json_when_environment_is_unset(self):
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.json"
            config_path.write_text(json.dumps({"trusted_hosts": ["Router.Home"]}))
            with patch.object(config_module, "CONFIG_PATH", config_path), patch.dict(os.environ, {}, clear=True):
                self.assertEqual(config_module.load_config()["trusted_hosts"], ["router.home"])


if __name__ == "__main__":
    unittest.main()
