#!/usr/bin/env python3
"""Validate the private Paperless endpoint file without printing its value."""
from pathlib import Path
import sys
from urllib.parse import urlsplit


def main():
    lines = Path(sys.argv[1]).read_text().splitlines()
    if len(lines) != 1 or not lines[0].startswith("PAPERLESS_URL="):
        raise ValueError("expected one PAPERLESS_URL setting")
    value = lines[0].removeprefix("PAPERLESS_URL=")
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.port is not None
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("PAPERLESS_URL must be one HTTPS origin without credentials or path")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, IndexError) as error:
        sys.exit(f"Paperless runtime settings rejected: {error}")
