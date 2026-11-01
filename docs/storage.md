# NVMe state and movable bulk media

The default limits apply to Immich alone: 32 GiB disposable rootfs, 256 GiB
/persist and 512 GiB /data, initially all on local-zfs (NVMe RAID10). These LXC ZFS
subvolumes use refquota, not preallocation; the installed Proxmox implementation
and parent dataset's absent reservations were verified read-only. Actual writes,
staged copies and snapshots consume space. Check the new datasets' properties
after provisioning too. A quota is neither reserved capacity nor protection from
pool exhaustion. Both persistent limits can be reviewed and grown later.

/persist remains on NVMe. It contains PostgreSQL, Redis, identities, Borg state,
dumps, thumbnails/previews, encoded videos, profile images and hot backup staging.
/data contains bulk original photos/videos, a consistent backup copy of those
originals, and temporary approved recovery scratch. It contains no live DB,
thumbnails, encoded videos or profile data.

## Native Immich layout

The NixOS mediaLocation is /persist/immich. Its thumbs, encoded-video, profile and
backups directories are ordinary directories on /persist. Only upload and library
are symlinks to /data/immich/upload and /data/immich/library. Both originals
directories therefore remain on the same filesystem for storage-template renames.
Moving the backing /data volume keeps all paths stored in Immich unchanged.

scripts/immich-layout validates links and initializes directories only after both
volume identities pass the storage gate. It refuses existing real upload/library
directories or unexpected links; it never silently migrates data. It leaves .immich
markers untouched, applies ownership only to directory roots, and never recursively
chowns the library on boot. No extra Proxmox volume or in-container bind mount is
needed. This repository has not yet been deployed, so there is no existing layout
to convert; a deployed contract-v1 layout would need a separate stopped migration.

[Immich's custom-location guide](https://docs.immich.app/guides/custom-locations/)
demonstrates filesystem mounts through Docker Compose. Its THUMB_LOCATION and
similar variables are compose substitutions, not native server options. The native
symlink approach here is an implementation choice informed by the pinned 3.3.5
storage source: normal file I/O and marker access follow these paths. Automated
filesystem tests cover physical placement, renames and refusal of wrong links.
Actual Immich startup/upload/transcode/replacement must still be validated on LXC.
Upstream empty-directory pruning uses lstat and skips a symlink root; do not assume
it will prune empty original-library directories in this layout.

Immich's aggregate storage metric uses its media root and will report /persist.
Monitor BOTH volumes explicitly with `df -h /persist /data`; the health helper also
prints both. Never rely on the UI to detect a full /data volume. Backups require
room for a second original-media copy on /data and a second hot-state copy on
/persist. We can revisit this overhead after validating the basic workflow.

Keeping thumbnails on NVMe reduces HDD activity; it does not guarantee spindown.
Opening/downloading originals, uploads, background jobs, backups, ZFS maintenance,
monitoring and host activity may wake disks. This change does not configure HDD
power management or the host's pool maintenance schedule.

## Later move of /data to HDD (separate approval batch)

Preconditions: a successful consistent backup and restore rehearsal; sufficient
hddpool capacity, a verified data-only layout, and exact current CT/volume IDs
recorded from pct config. Capture the manifest, config, dataset properties and
checksums of representative originals and hot files. Stop backup timer, wait for
any backup, hold /persist/operation.lock, and stop the container as deployment.md
describes. Never migrate /persist or change application paths.

On the host, only after approving this exact batch with CT replaced by the actual
current ID:

```sh
CT=REPLACE_WITH_CURRENT_CONTAINER_ID
pct status "$CT"  # must be stopped
pct config "$CT"
pvesm set hddpool --content images,rootdir
pct move-volume "$CT" mp1 hddpool --delete 0
pct config "$CT"
```

This uses the installed supported move-volume operation. --delete 0 retains the
source volume as an unused entry rather than deleting it. Verify new mp1 identity,
size, backup flag and mount path and record the unused source volume. Leave mp0 on
local-zfs. Then approved `pct start "$CT"`, run health-check and compare realpath,
checksums and actual Immich media reads. No source cleanup is part of this batch.

On failure before writes to the new copy, leave the container stopped and prepare
a separately reviewed reattachment batch from the captured configs. After writes,
the old copy is stale: preserve both and reconcile/restore instead of blindly
reattaching it. Do not delete persistent volumes or run both copies concurrently.
