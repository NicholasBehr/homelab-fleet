#!/usr/bin/env python3
"""Validate SFTP-only rclone settings without exposing credential values."""
import configparser
import os
from pathlib import Path
import stat
import sys


def validate_key_file(path: Path, secrets_directory: Path) -> None:
    if path.parent != secrets_directory or path.name in ("", ".", ".."):
        raise ValueError("SFTP key file must be directly under /persist/secrets")
    directory = secrets_directory.lstat()
    if (
        not stat.S_ISDIR(directory.st_mode)
        or directory.st_uid != 0
        or directory.st_gid != 0
        or stat.S_IMODE(directory.st_mode) != 0o700
    ):
        raise ValueError("SFTP credential directory is unsafe")
    info = path.lstat()
    if (
        not stat.S_ISREG(info.st_mode)
        or info.st_uid != 0
        or info.st_gid != 0
        or stat.S_IMODE(info.st_mode) not in (0o400, 0o600)
        or info.st_size == 0
    ):
        raise ValueError("SFTP key file must be a non-empty root-only regular file")


def validate(
    config_path: Path,
    remote_name: str,
    known_hosts: Path,
    secrets_directory: Path,
) -> None:
    parser = configparser.ConfigParser(interpolation=None)
    try:
        with config_path.open(encoding="utf-8") as config_file:
            parser.read_file(config_file)
    except (OSError, UnicodeError, configparser.Error):
        raise ValueError("rclone configuration is unreadable or invalid") from None

    if not parser.has_section(remote_name):
        raise ValueError("configured SFTP remote is missing")
    remote = parser[remote_name]
    required = {
        "type": "sftp",
        "shell_type": "none",
        "disable_hashcheck": "true",
        "skip_links": "true",
        "known_hosts_file": str(known_hosts),
    }
    if any(
        remote.get(name, "") != value
        if name == "known_hosts_file"
        else remote.get(name, "").lower() != value
        for name, value in required.items()
    ):
        raise ValueError("rclone remote must use pinned SFTP without shell commands")
    if not remote.get("host", "").strip() or not remote.get("user", "").strip():
        raise ValueError("SFTP host and user are required")

    has_password = bool(remote.get("pass", "").strip())
    has_inline_key = bool(remote.get("key_pem", "").strip())
    key_file = remote.get("key_file", "").strip()
    if key_file:
        validate_key_file(Path(key_file), secrets_directory)
    if not (has_password or has_inline_key or key_file):
        raise ValueError("SFTP authentication must be configured")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("Usage: validate-rclone-config.py CONFIG REMOTE KNOWN_HOSTS SECRETS_DIR")
    try:
        validate(
            Path(sys.argv[1]),
            sys.argv[2],
            Path(sys.argv[3]),
            Path(sys.argv[4]),
        )
    except (OSError, ValueError) as error:
        sys.exit(f"SFTP configuration rejected: {error}")
