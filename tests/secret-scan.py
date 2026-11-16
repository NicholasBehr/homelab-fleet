"""Reject common private-key/plaintext credential accidents in tracked source."""
from pathlib import Path
import re
import subprocess
paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z']).decode().split('\0')
patterns = [r'AGE-SECRET-' + r'KEY-1[0-9A-Z]+', r'-----BEGIN (?:OPENSSH|RSA|EC|DSA|PGP) PRIVATE ' + r'KEY', r'tskey-' + r'(?:auth|api)-[A-Za-z0-9_-]+', r'gh[pousr]_' + r'[A-Za-z0-9]{30,}']
for name in filter(None, paths):
    if not Path(name).is_file():
        continue
    text = Path(name).read_text(errors='replace')
    for pattern in patterns:
        if re.search(pattern, text): raise SystemExit(f'Possible plaintext secret in {name}')
print('Tracked-source secret pattern check passed (not a proof of absence).')
