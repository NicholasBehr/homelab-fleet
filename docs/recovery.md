# Recovery

Use the local Proxmox console if Tailscale fails; do not open LAN ports as a shortcut.
From authenticated host root: `pct status ID`, `pct config ID`, `pct enter ID`.
Check `systemctl --failed`, `journalctl -b`, mount identity, free space, age key
permissions, sops-nix, tailscaled state and Serve configuration. Never print secrets.

Missing/wrong mounts: stop the container, compare mp0/mp1 to the last deployment
record, reattach only the identified volumes after approval. Do not write markers
to unidentified existing storage. Never initialize a database to hide a mount error.

Lost rootfs, intact volumes: verify the original container stopped, create a fresh
rootfs from the exact compatible release, transfer managed mounts as deployment.md,
and start/check it. Identity and data remain. No destructive cleanup is included.

Bad software update before migrations: stop NEW and transfer volumes back only
when schema compatibility is established. Unknown compatibility means restore a
pre-update archive into new volumes with the matching version. Retain failed state.

Lost all volumes/age key: use independent 1Password recovery credentials, new volumes,
new age recipient and the fresh-volume procedure in backup-restore.md. Tailnet
identity can be re-enrolled after revoking the lost node. Backup access does not
require the lost age key. Validate media, DB, extensions and authentication before
making the restored instance available. Never run two instances of one identity.

If Intel acceleration fails: collect render PCI mapping, `vainfo --display drm
--device /dev/dri/renderD128`, service journal and FFmpeg error, plus host i915
logs and Secure Boot state read-only. Report evidence and options before changing
drivers/confinement. CPU transcoding is a possible explicit temporary choice;
no experimental driver, VF, DKMS or Secure Boot bypass is authorized.
