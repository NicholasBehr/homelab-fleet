# Architecture

A Proxmox veth provides outbound DHCP connectivity. Each container owns a Tailscale
identity, SSH policy and HTTPS Serve endpoint; Immich binds 127.0.0.1:2283. No
ordinary sshd, LAN application listener or Funnel is enabled. The container
firewall trusts only tailscale0. Tailnet ACLs supplement Immich authentication.

Rootfs, `/nix`, generated machine-id, ML models and transient caches are discarded
on replacement. Stable identity resides in `/persist/tailscale/tailscaled.state`.
Ordinary SSH host keys do not exist because sshd is disabled. Root is declarative
and locked; authenticated host administrators recover using `pct enter ID`.
Machine-id intentionally regenerates: nothing in this service uses it as identity.

| Location | Meaning | Backup |
|---|---|---|
| /persist/secrets/age-key.txt | unique logical-container age key | encrypted Borg; independent recovery recipient in 1Password |
| /persist/tailscale | node credentials and preferences | encrypted Borg; revoke/re-enroll if identity lost or cloned |
| /persist/postgresql/17 | live DB | excluded; logical dump included instead |
| /persist/redis | persistent queue | excluded; quiesced copy in /persist/backup/redis |
| /persist/backup | compatible dump and version metadata | included |
| /persist/borg/config | keys and security state | included; recovery escrow independent |
| /persist/borg/cache | rebuildable cache | retained locally, excluded from Borg |
| /persist/borg/known_hosts | verified SSH trust anchor | included |
| /persist/immich | thumbnails/previews, encoded video, profile, built-in backups; upload/library links | excluded live; hot staging included |
| /persist/backup/immich-hot | consistent hot-state staging, without links to originals | included |
| /data/immich/upload and /data/immich/library | bulk original photos/videos and their integrity markers only | backed up via staged copy |
| /data/.backup-stage/media | consistent media staging tree | included, no second live traversal |
| /var/cache/immich | ML model downloads | rebuildable, not essential |
| /var/lib/immich | module-created state directory | application root is /persist/immich, originals physically live on /data/immich |

`/persist` always remains on the NVMe RAID10. `/data` starts on NVMe too and may
later move alone to the three-HDD RAIDZ1. Its only application data is original
media; bulk backup staging and approved recovery scratch may also live there.
Thumbnails/previews, profile images, encoded video, DBs and DB dumps stay on NVMe.
See [storage layout and migration](storage.md) for links, capacity and sleep limits.

No all-of-/var persistence or impermanence is needed. Services use persistent
paths directly. The storage gate checks actual mountpoints, separate backing
filesystems from root, and expected marker values. Markers detect wrong accidental
attachments, not malicious host actions; verify volume IDs with pct config too.
Volumes must exist before init; markers are written only by approved provisioning.
A failed gate blocks database, Redis, Immich, secrets-readiness and tailscaled.

Proxmox dev0 exposes only the verified Intel render node, mode 0660, container
root:render (GID 303). Immich UID/GID is fixed at 1100, Redis at 1101, PostgreSQL at 71. Volume roots are root-owned mode0711 for traversal; service subdirectories are mode0700. Default unprivileged ID
ranges map these to host 101100 and 100303; no broad host render-group mapping or
world-writable permissions. dev1 supplies TUN. No nesting, FUSE, privileged mode,
AppArmor bypass, VF, DKMS, kernel flags or Secure Boot exception is configured.

Reference sources checked during implementation:
- [Pinned stable modules](https://github.com/NixOS/nixpkgs/tree/fa1373130d5a21c040a47c5dbe1913d59ed91808/nixos/modules)
- [Pinned Immich module](https://github.com/NixOS/nixpkgs/blob/1c89083e451e891152365b799595cf7790a43325/nixos/modules/services/web-apps/immich.nix)
- [Proxmox container manual](https://pve.proxmox.com/pve-docs/pct.1.html)
- [Hetzner Borg/SSH](https://docs.hetzner.com/storage/storage-box/access/access-ssh-rsync-borg/)
- [Immich hardware transcoding configuration](https://docs.immich.app/features/hardware-transcoding/)
- [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve)

Installed `pct help set` and `pct help move-volume` were also inspected read-only.
Runtime namespace restrictions and device cgroups still need actual LXC tests.
Do not disable confinement to make a failed test pass; investigate and propose
specific options before changing the contract.
