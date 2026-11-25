"""Tests for the loopback-only Jellyfin listener configuration."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace

import importlib.util

SCRIPT = Path(__file__).resolve().parents[1] / "network-config.py"
TEMPLATE = """<?xml version="1.0"?>
<NetworkConfiguration>
  <InternalHttpPort>8096</InternalHttpPort>
  <PublicHttpPort>8096</PublicHttpPort>
  <EnableHttps>false</EnableHttps>
  <RequireHttps>false</RequireHttps>
  <AutoDiscovery>false</AutoDiscovery>
  <EnableUPnP>false</EnableUPnP>
  <EnableIPv4>true</EnableIPv4>
  <EnableIPv6>false</EnableIPv6>
  <LocalNetworkAddresses><string>127.0.0.1</string></LocalNetworkAddresses>
</NetworkConfiguration>
"""

SPEC = importlib.util.spec_from_file_location("network_config", SCRIPT)
NETWORK_CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NETWORK_CONFIG)


class NetworkConfigTests(unittest.TestCase):
    def run_config(self, path, template):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(path),
                str(template),
                str(os.getuid()),
                str(os.getgid()),
                "8096",
            ],
            capture_output=True,
            text=True,
        )

    def test_seeds_loopback_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "network.xml"
            template = root / "template.xml"
            template.write_text(TEMPLATE)

            result = self.run_config(path, template)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("<string>127.0.0.1</string>", path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_same_identity_install_does_not_require_chown(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "network.xml"
            template = root / "template.xml"
            template.write_text(TEMPLATE)

            with (
                mock.patch.object(
                    NETWORK_CONFIG.os,
                    "fstat",
                    return_value=SimpleNamespace(
                        st_uid=os.geteuid(), st_gid=os.getegid()
                    ),
                ),
                mock.patch.object(
                    NETWORK_CONFIG.os,
                    "fchown",
                    side_effect=PermissionError("fchown is unavailable"),
                ) as fchown,
            ):
                NETWORK_CONFIG.install_if_missing(path, template, os.geteuid(), os.getegid())

            fchown.assert_not_called()

    def test_preserves_valid_existing_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "network.xml"
            template = root / "template.xml"
            template.write_text(TEMPLATE)
            path.write_text(TEMPLATE)
            os.chown(path, os.getuid(), os.getgid())
            path.chmod(0o600)

            result = self.run_config(path, template)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(path.read_text(), TEMPLATE)

    def test_rejects_non_loopback_listener_without_overwriting_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "network.xml"
            template = root / "template.xml"
            template.write_text(TEMPLATE)
            changed = TEMPLATE.replace("127.0.0.1", "0.0.0.0")
            path.write_text(changed)

            result = self.run_config(path, template)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_text(), changed)

    def test_rejects_symlinked_network_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target.xml"
            path = root / "network.xml"
            template = root / "template.xml"
            target.write_text(TEMPLATE)
            template.write_text(TEMPLATE)
            path.symlink_to(target)

            result = self.run_config(path, template)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), TEMPLATE)


if __name__ == "__main__":
    unittest.main()
