#!/usr/bin/env python3
"""Publish only current, fully copied remote files without overwriting media."""
from datetime import datetime
import json
from pathlib import Path, PurePosixPath
import os
import sys


def matches(path: Path, size: int, modified: datetime) -> bool:
    info = path.stat()
    return (
        info.st_size == size
        and abs(int(info.st_mtime) - int(modified.timestamp())) <= 1
    )


def safe_path(root: Path, relative: PurePosixPath) -> Path:
    current = root
    for component in relative.parts:
        current = current / component
        if current.is_symlink():
            raise ValueError(f"refusing symlinked media path: {current}")
    return current


def promote(staging: Path, library: Path, entries: list[dict]) -> None:
    if staging.is_symlink() or not staging.is_dir():
        raise ValueError(f"unsafe staging directory: {staging}")
    if library.is_symlink() or not library.is_dir():
        raise ValueError(f"unsafe library directory: {library}")

    pending = []
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("IsDir") is not False:
            raise ValueError("remote file listing has an invalid entry")
        name = entry.get("Path")
        size = entry.get("Size")
        modified_text = entry.get("ModTime")
        if (
            not isinstance(name, str)
            or not isinstance(size, int)
            or size < 0
            or not isinstance(modified_text, str)
        ):
            raise ValueError("remote file listing is missing file metadata")

        relative = PurePosixPath(name)
        if relative.is_absolute() or not relative.parts or ".." in relative.parts:
            raise ValueError("remote file listing contains an unsafe path")
        modified = datetime.fromisoformat(modified_text.replace("Z", "+00:00"))
        source = safe_path(staging, relative)
        destination = safe_path(library, relative)

        if source.exists():
            if not source.is_file() or not matches(source, size, modified):
                raise ValueError(f"staged file does not match the remote listing: {name}")
        elif destination.exists() and destination.is_file() and matches(
            destination, size, modified
        ):
            continue
        else:
            raise FileNotFoundError(f"completed staged file is missing: {name}")

        if destination.exists():
            if destination.is_file() and matches(destination, size, modified):
                continue
            raise FileExistsError(f"library destination differs from remote file: {name}")
        pending.append((source, destination))

    for source, destination in pending:
        destination_parent = destination.parent
        destination_parent.mkdir(parents=True, exist_ok=True)
        os.link(source, destination, follow_symlinks=False)
        source.unlink()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: promote.py STAGING LIBRARY")
    try:
        manifest = json.load(sys.stdin)
        if not isinstance(manifest, list):
            raise ValueError("remote file listing must be a JSON array")
        promote(Path(sys.argv[1]), Path(sys.argv[2]), manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        sys.exit(f"Media promotion failed: {error}")
