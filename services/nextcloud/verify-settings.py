"""Validate the runtime public endpoint without printing its value or JSON."""
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit


def valid(value):
    if not isinstance(value, dict) or set(value) != {"trusted_domains", "overwrite.cli.url"}:
        return False
    domains = value["trusted_domains"]
    if not isinstance(domains, list) or not all(isinstance(d, str) for d in domains):
        return False
    endpoint = urlsplit(value["overwrite.cli.url"])
    host = endpoint.hostname
    return (
        endpoint.scheme == "https"
        and host is not None
        and host.endswith(".ts.net")
        and endpoint.netloc == host
        and endpoint.path in ("", "/")
        and not endpoint.query
        and not endpoint.fragment
        and len(domains) == 3
        and set(domains) == {"localhost", "127.0.0.1", host}
    )


def main():
    try:
        if valid(json.loads(Path(sys.argv[1]).read_text())):
            return 0
    except (ValueError, TypeError, OSError, IndexError):
        pass
    print("Invalid Nextcloud endpoint settings; expected the documented tailnet-only schema", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
