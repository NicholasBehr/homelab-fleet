"""Synthetic validation of private Zigbee2MQTT enrollment files."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify-zigbee-runtime.py"
NETWORK_KEY = [42, 9, 88, 2, 17, 64, 201, 4, 91, 33, 18, 72, 5, 222, 31, 140]


class ZigbeeRuntime(unittest.TestCase):
    def validate(self, *, endpoint="coordinator.example:7638", key=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            settings = root / "zigbee2mqtt.env"
            secret = root / "zigbee2mqtt.yaml"
            settings.write_text(
                "ZIGBEE2MQTT_CONFIG_SERIAL_PORT=tcp://"
                + endpoint
                + "\nZIGBEE2MQTT_CONFIG_ADVANCED_CHANNEL=15\n"
                + "ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID=23451\n"
                + "ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID=[9,8,7,6,5,4,3,2]\n"
            )
            secret.write_text("network_key: " + json.dumps(key or NETWORK_KEY) + "\n")
            return subprocess.run(
                ["python3", str(SCRIPT), str(settings), str(secret)],
                capture_output=True,
            )

    def test_valid_fresh_network(self):
        self.assertEqual(self.validate().returncode, 0)

    def test_rejects_default_network_key(self):
        default = [1, 3, 5, 7, 9, 11, 13, 15, 0, 2, 4, 6, 8, 10, 12, 13]
        self.assertNotEqual(self.validate(key=default).returncode, 0)

    def test_rejects_wrong_radio_port(self):
        self.assertNotEqual(self.validate(endpoint="coordinator.example:6638").returncode, 0)

if __name__ == "__main__":
    unittest.main()
