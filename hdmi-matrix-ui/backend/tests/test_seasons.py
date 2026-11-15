"""Runs the Node test suite for the web app's seasonal themes.

The date rules and palettes live in frontend/seasons.js (plain JS, shared with the browser), so
the tests are written in Node's built-in runner. Skipped when Node isn't installed.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

NODE = shutil.which("node")


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_seasonal_themes_node_suite():
    result = subprocess.run(
        [NODE, "--test", str(Path(__file__).with_name("seasons.test.js"))],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
