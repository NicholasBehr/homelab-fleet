#!/usr/bin/env python3
"""Validate the private Zigbee2MQTT runtime enrollment."""

import json
from pathlib import Path
import re
import sys


DEFAULT_NETWORK_KEY = [1, 3, 5, 7, 9, 11, 13, 15, 0, 2, 4, 6, 8, 10, 12, 13]
ALLOWED_CHANNELS = {11, 15, 20, 25}
PORT_PATTERN = re.compile(r"tcp://[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?:7638")


def read_environment(path):
    settings = {}
    for raw_line in Path(path).read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("invalid Zigbee2MQTT runtime setting")
        key, value = line.split("=", 1)
        if key in settings or not key or not value:
            raise ValueError("invalid Zigbee2MQTT runtime setting")
        settings[key] = value
    expected = {
        "ZIGBEE2MQTT_CONFIG_SERIAL_PORT",
        "ZIGBEE2MQTT_CONFIG_ADVANCED_CHANNEL",
        "ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID",
        "ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID",
    }
    if set(settings) != expected:
        raise ValueError("unexpected Zigbee2MQTT runtime settings")
    if not PORT_PATTERN.fullmatch(settings["ZIGBEE2MQTT_CONFIG_SERIAL_PORT"]):
        raise ValueError("coordinator endpoint must use wired TCP port 7638")
    if settings["ZIGBEE2MQTT_CONFIG_SERIAL_PORT"] == "tcp://runtime.invalid:7638":
        raise ValueError("coordinator endpoint is not enrolled")
    try:
        channel = int(settings["ZIGBEE2MQTT_CONFIG_ADVANCED_CHANNEL"])
    except ValueError as error:
        raise ValueError("invalid Zigbee channel") from error
    if channel not in ALLOWED_CHANNELS:
        raise ValueError("Zigbee channel must be 11, 15, 20 or 25")
    try:
        pan_id = int(settings["ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID"])
        extended_pan_id = json.loads(settings["ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID"])
    except (ValueError, json.JSONDecodeError) as error:
        raise ValueError("invalid Zigbee network identity") from error
    if not 1 <= pan_id <= 0xFFFE:
        raise ValueError("invalid Zigbee PAN ID")
    if len(extended_pan_id) != 8 or any(
        not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
        for value in extended_pan_id
    ):
        raise ValueError("invalid Zigbee extended PAN ID")


def read_network_key(path):
    match = re.fullmatch(r"\s*network_key:\s*(\[[^\n]+\])\s*", Path(path).read_text())
    if not match:
        raise ValueError("invalid Zigbee network-key document")
    try:
        key = json.loads(match.group(1))
    except json.JSONDecodeError as error:
        raise ValueError("invalid Zigbee network-key document") from error
    if (
        len(key) != 16
        or any(not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255 for value in key)
        or key == DEFAULT_NETWORK_KEY
    ):
        raise ValueError("Zigbee network key must be a non-default 128-bit key")


def main():
    if len(sys.argv) != 3:
        raise ValueError("expected settings and network-key paths")
    read_environment(sys.argv[1])
    read_network_key(sys.argv[2])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        sys.exit(f"Zigbee2MQTT enrollment rejected: {error}")
