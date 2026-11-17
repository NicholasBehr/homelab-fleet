"""Synthetic checks for atomic Zigbee2MQTT enrollment."""

import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "enroll-zigbee2mqtt.py"
SPEC = importlib.util.spec_from_file_location("zigbee2mqtt_enrollment", SCRIPT)
ENROLLMENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENROLLMENT)


class ZigbeeEnrollment(unittest.TestCase):
    def test_creates_private_files_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            ENROLLMENT.enroll(directory, "coordinator.example", 15)
            settings = directory / "zigbee2mqtt.env"
            network_key = directory / "zigbee2mqtt.yaml"
            self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(network_key.stat().st_mode), 0o600)
            key = json.loads(network_key.read_text().split(":", 1)[1])
            self.assertEqual(len(key), 16)
            with self.assertRaises(FileExistsError):
                ENROLLMENT.enroll(directory, "replacement.example", 20)

    def test_rejects_host_with_port_or_shell_syntax(self):
        for host in ("coordinator.example:7638", "$(command)", "name value"):
            with self.assertRaises(ValueError):
                ENROLLMENT.validate_host(host)

    def test_accepts_supported_channels_only(self):
        self.assertEqual(ENROLLMENT.validate_channel("25"), 25)
        for channel in ("12", "not-a-channel"):
            with self.assertRaises(ValueError):
                ENROLLMENT.validate_channel(channel)


if __name__ == "__main__":
    unittest.main()
