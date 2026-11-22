"""Validate that rclone cannot use remote shell commands or unpinned SFTP."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "validate-rclone-config.py"


class RcloneConfigTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.secrets = self.root / "secrets"
        self.secrets.mkdir(mode=0o700)
        self.config = self.root / "rclone.conf"
        self.known_hosts = self.secrets / "known_hosts"
        self.known_hosts.write_text("synthetic host key\n")

    def tearDown(self):
        self.temporary.cleanup()

    def write_config(self, **overrides):
        values = {
            "type": "sftp",
            "host": "sftp.example.invalid",
            "user": "media-reader",
            "pass": "synthetic-obscured-password",
            "known_hosts_file": str(self.known_hosts),
            "shell_type": "none",
            "disable_hashcheck": "true",
            "skip_links": "true",
        }
        values.update(overrides)
        self.config.write_text(
            "[source]\n"
            + "".join(f"{key} = {value}\n" for key, value in values.items())
        )

    def run_validator(self):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(self.config),
                "source",
                str(self.known_hosts),
                str(self.secrets),
            ],
            capture_output=True,
            text=True,
        )

    def test_accepts_pinned_sftp_without_remote_shell(self):
        self.write_config()

        result = self.run_validator()

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_shell_access(self):
        self.write_config(shell_type="unix")

        result = self.run_validator()

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("synthetic-obscured-password", result.stderr)

    def test_rejects_missing_host_key_validation(self):
        self.write_config(known_hosts_file="none")

        result = self.run_validator()

        self.assertNotEqual(result.returncode, 0)

    def test_requires_authentication(self):
        self.write_config(**{"pass": ""})

        result = self.run_validator()

        self.assertNotEqual(result.returncode, 0)

    def test_key_file_must_be_root_only_and_inside_secrets(self):
        key = self.secrets / "sftp-key"
        key.write_text("synthetic private key")
        key.chmod(0o600)
        if os.geteuid() == 0:
            os.chown(self.secrets, 0, 0)
            os.chown(key, 0, 0)
            self.secrets.chmod(0o700)
        self.write_config(**{"pass": "", "key_file": str(key)})

        result = self.run_validator()

        self.assertEqual(result.returncode == 0, os.geteuid() == 0, result.stderr)

    def test_rejects_key_file_outside_secrets(self):
        key = self.root / "sftp-key"
        key.write_text("synthetic private key")
        self.write_config(**{"pass": "", "key_file": str(key)})

        result = self.run_validator()

        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
