#!/usr/bin/env python3
"""Create the root-only Zigbee2MQTT runtime enrollment without exposing its key."""

import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys


SECRET_DIRECTORY = Path("/persist/secrets")
SETTINGS_FILE = SECRET_DIRECTORY / "zigbee2mqtt.env"
NETWORK_KEY_FILE = SECRET_DIRECTORY / "zigbee2mqtt.yaml"
HOST_PATTERN = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?")
ALLOWED_CHANNELS = {11, 15, 20, 25}


def validate_host(value):
    if not HOST_PATTERN.fullmatch(value):
        raise ValueError("enter a DNS name or IPv4 address without a port")
    return value


def validate_channel(value):
    try:
        channel = int(value)
    except ValueError as error:
        raise ValueError("channel must be 11, 15, 20 or 25") from error
    if channel not in ALLOWED_CHANNELS:
        raise ValueError("channel must be 11, 15, 20 or 25")
    return channel


def verify_directory(directory):
    info = directory.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != 0
        or info.st_gid != 0
        or stat.S_IMODE(info.st_mode) != 0o700
    ):
        raise ValueError("/persist/secrets must be root:root mode0700")


def stage(directory, name, content):
    path = directory / name
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    return path


def enroll(directory, host, channel):
    settings = directory / "zigbee2mqtt.env"
    network_key = directory / "zigbee2mqtt.yaml"
    if settings.exists() or settings.is_symlink() or network_key.exists() or network_key.is_symlink():
        raise FileExistsError("Zigbee2MQTT enrollment already exists")

    pan_id = secrets.randbelow(0xFFFE) + 1
    extended_pan_id = list(secrets.token_bytes(8))
    staged_settings = stage(
        directory,
        ".zigbee2mqtt.env.new",
        f"ZIGBEE2MQTT_CONFIG_SERIAL_PORT=tcp://{host}:7638\n"
        f"ZIGBEE2MQTT_CONFIG_ADVANCED_CHANNEL={channel}\n"
        f"ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID={pan_id}\n"
        "ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID="
        + json.dumps(extended_pan_id, separators=(",", ":"))
        + "\n",
    )
    staged_key = None
    installed = []
    try:
        key = list(secrets.token_bytes(16))
        staged_key = stage(
            directory,
            ".zigbee2mqtt.yaml.new",
            "network_key: " + json.dumps(key, separators=(",", ":")) + "\n",
        )
        os.link(staged_settings, settings, follow_symlinks=False)
        installed.append(settings)
        os.link(staged_key, network_key, follow_symlinks=False)
        installed.append(network_key)
        directory_descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except Exception:
        for path in installed:
            path.unlink(missing_ok=True)
        raise
    finally:
        staged_settings.unlink(missing_ok=True)
        if staged_key is not None:
            staged_key.unlink(missing_ok=True)


def main():
    if os.geteuid() != 0:
        raise PermissionError("run zigbee2mqtt-enroll from the root console")
    verify_directory(SECRET_DIRECTORY)
    host = validate_host(input("Coordinator DNS name or IPv4 address: ").strip())
    channel = validate_channel(input("Fresh Zigbee channel (11, 15, 20 or 25): ").strip())
    enroll(SECRET_DIRECTORY, host, channel)
    print("Zigbee2MQTT runtime enrollment created")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"Zigbee2MQTT enrollment failed: {error}")
