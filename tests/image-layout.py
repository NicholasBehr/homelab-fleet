"""Image layout guard: never ship runtime identities, state volumes or secret files."""
import sys
import tarfile
from pathlib import PurePosixPath
with tarfile.open(sys.argv[1], mode='r|*') as archive:
    init = False
    for member in archive:
        path = PurePosixPath(member.name)
        name = str(path).lstrip('/')
        if '..' in path.parts:
            raise SystemExit('Unsafe template path')
        if name == 'sbin/init': init = True
        if name == 'etc/systemd/system/multi-user.target.wants/homelab-operational.target':
            raise SystemExit('Template contains operational activation')
        if name == 'var/lib/homelab/operational-enabled':
            raise SystemExit('Template contains the operational activation record')
        if name.startswith(('persist/', 'data/', 'run/secrets/')) and not member.isdir():
            raise SystemExit(f'Runtime state present in template: {name}')
    if not init: raise SystemExit('LXC init missing')
print('Template has init and no runtime files on persistent mounts or /run/secrets.')
