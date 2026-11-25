#!/usr/bin/env python3
"""Create and validate Jellyfin's loopback-only first-start network config."""
import os
from pathlib import Path
import stat
import sys
import tempfile
import xml.etree.ElementTree as ET


def validate(path: Path, uid: int, gid: int, port: int) -> None:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError("network configuration must be a regular file")
    if info.st_uid != uid or info.st_gid != gid or stat.S_IMODE(info.st_mode) & 0o600 != 0o600:
        raise ValueError("network configuration must be writable by the Jellyfin service")
    root = ET.parse(path).getroot()
    if root.tag != "NetworkConfiguration":
        raise ValueError("unexpected Jellyfin network configuration root")

    required = {
        "InternalHttpPort": str(port),
        "PublicHttpPort": str(port),
        "EnableHttps": "false",
        "RequireHttps": "false",
        "AutoDiscovery": "false",
        "EnableIPv4": "true",
        "EnableIPv6": "false",
    }
    for name, value in required.items():
        if root.findtext(name, "").lower() != value:
            raise ValueError(f"Jellyfin network setting must be {name}={value}")

    # Jellyfin 10.11 may omit this element when its UI saves the disabled
    # default. Absence is therefore equivalent to false, but an explicit true
    # must still fail closed.
    upnp = root.findtext("EnableUPnP")
    if upnp is not None and upnp.lower() != "false":
        raise ValueError("Jellyfin network setting must be EnableUPnP=false")

    addresses = root.find("LocalNetworkAddresses")
    if addresses is None or [entry.text for entry in addresses.findall("string")] != [
        "127.0.0.1"
    ]:
        raise ValueError("Jellyfin must bind only to 127.0.0.1")


def install_if_missing(path: Path, template: Path, uid: int, gid: int) -> None:
    if path.is_symlink():
        raise ValueError("refusing symlinked Jellyfin network configuration")
    if path.exists():
        return

    descriptor, temporary = tempfile.mkstemp(prefix=".network.xml.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(template.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
            info = os.fstat(stream.fileno())
            if info.st_uid != uid or info.st_gid != gid:
                os.fchown(stream.fileno(), uid, gid)
            os.fchmod(stream.fileno(), 0o600)
        os.link(temporary, path, follow_symlinks=False)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main() -> None:
    if len(sys.argv) != 6:
        sys.exit("Usage: network-config.py PATH TEMPLATE UID GID PORT")
    path, template = Path(sys.argv[1]), Path(sys.argv[2])
    try:
        uid, gid, port = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
        install_if_missing(path, template, uid, gid)
        validate(path, uid, gid, port)
    except (OSError, ValueError, ET.ParseError) as error:
        sys.exit(f"Jellyfin network configuration rejected: {error}")


if __name__ == "__main__":
    main()
