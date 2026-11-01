# Manual replacement

Every host mutation needs explicit approval of the selected batch. Do not execute
this procedure on real data until the disposable transfer test in host-plan.md
has passed. No routine nixos-rebuild. Do not replace an archive under an existing
release identity; use a new full commit.

## Preflight while service still runs

Download/verify an explicit release as in provisioning.md, with VARIANT=immich.
Inspect manifest against `provision/containers.nix`. Record old/new CT IDs and exact
root/mp0/mp1 volume IDs from `pct config OLD`; save configuration off-host using
`ssh root@pve.dorper-shade.ts.net 'pct config 200' > old-config.txt` on Mac.
Record compatible Immich, PostgreSQL, vector extension and backup versions. Read
upstream migration notes; PostgreSQL major upgrades need dump/restore or a separate
migration procedure and are NOT normal rootfs replacements. Check both filesystems,
bulk and hot-state staging headroom on their respective volumes, rootfs capacity, age key presence, ciphertext recipients,
known_hosts, DB health and latest successful recoverable Borg archive.

Existing ROOTFS stays attached to OLD; NEW receives a fresh rootfs. Managed mp0/mp1
transfer with `pct move-volume --target-vmid` changes their container assignment.
Both containers must stay stopped during transfer. Do not detach using --delete,
reuse an existing container ID, create a copy of a Tailscale identity, or use pct
destroy. Never start both containers with the same state.

## Approved change batch

Set OLD/NEW from the current contract, not from memory. For the first transition:

```sh
OLD=200
NEW=201
# ARCHIVE already downloaded and verified, as in provisioning.md.
test ! -e "/etc/pve/lxc/$NEW.conf"
pct config "$OLD"
pct exec "$OLD" -- systemctl stop borgbackup-job-immich.timer
```

Stop the timer, then wait for any active backup to finish. If the old image is the
secret-free bootstrap, there is no timer, database or user media yet: instead
record an off-host encrypted recovery copy of its age identity through a protected
file transfer (never display it). A bootstrap-to-operational transition must have
no application data; otherwise treat it as an operational update.

For operational updates, obtain an application-consistent archive and require a
successful job result. `systemctl start` waits for this oneshot job:

```sh
pct exec "$OLD" -- systemctl start borgbackup-job-immich.service
pct exec "$OLD" -- systemctl show borgbackup-job-immich.service -p Result -p ExecMainStatus
```

Abort on any nonzero exit, warning or failed Result. Verify the completed archive
using the Borg wrapper and its versions metadata; do a restore rehearsal before a
migration-bearing update. Do not proceed while production backups are unconfigured.
A preparation failure runs cleanup; verify application services recovered.

Acquire the same per-service lock used by backups, then shut down. Run this inside
one approved `pct enter OLD` session, and leave it held until shutdown:

```sh
exec 9>/persist/operation.lock
flock -n 9
systemctl stop immich-server.service immich-machine-learning.service
systemctl poweroff
```

For bootstrap, acquire the lock then poweroff without the nonexistent Immich stop.
The backup service cannot run while this lock is held. Confirm `pct status OLD`
is stopped; do not force-stop unless separately approved. Timer remains stopped
in the old rootfs, preventing a new scheduled backup between backup and shutdown.
No writes may occur after the recovery point except those explicitly documented:
the application can briefly resume after backup completion; for a migration-bearing
update take a second final dump/media sync while holding the lock and create a
final archive before poweroff, using the procedure in backup-restore.md. This final
archive is the rollback recovery point, not the earlier rehearsal archive.

On the host, with OLD confirmed stopped:

```sh
pct set "$OLD" --onboot 0
pct create "$NEW" "local:vztmpl/$ARCHIVE" --ostype nixos --unprivileged 1   --hostname immich --cores 6 --memory 12288 --swap 0 --onboot 0   --rootfs local-zfs:32   --net0 name=eth0,bridge=vmbr0,ip=dhcp,ip6=manual,firewall=1   --dev0 /dev/dri/renderD128,uid=0,gid=303,mode=0660   --dev1 /dev/net/tun,uid=0,gid=0,mode=0600
pct move-volume "$OLD" mp0 --target-vmid "$NEW" --target-volume mp0
pct move-volume "$OLD" mp1 --target-vmid "$NEW" --target-volume mp1
pct config "$OLD"
pct config "$NEW"
```

Check volume IDs, mount paths, backup flags, container ID maps and owner mappings
before starting. No copy, recursive chown, deletion or reinitialization is allowed.
If only one transfer succeeds, leave both stopped and transfer it back; inspect
configs after every operation. The old rootfs and any unused entries remain.

```sh
pct start "$NEW"
pct exec "$NEW" -- health-check
pct exec "$NEW" -- journalctl -b -u storage-contract -u operational-ready -u postgresql -u immich-server --no-pager
```

health-check intentionally returns failure while backups are unconfigured. Inspect
Tailscale identity/IP unchanged, HTTPS login from authorized Mac, unauthorized-access
denial, DB row counts/assets, volumes, and real hardware transcoding. Verify old
CT is stopped. Record commit, archive digest, CT IDs, volume IDs, versions, backup
archive and results on `/persist/deployment-record.txt` through an explicitly
approved operator command, and retain a copy off-host. Update the contract's current
and next free ID in Git. Set onboot=1 only in a separately approved finalization.

Do not delete OLD in this batch. It has no persistent mounts after transfer, but
validate this plus unused-volume ownership before any later cleanup request.

## Failure and recovery

If NEW has not started/migrated data, stop it, reverse the two move-volume operations
back to OLD, validate configs, and start OLD with approval. If migration may have
occurred, do NOT start older software against changed state. Restore the final
pre-update consistent archive into separate empty volumes with the matching old
image; keep failed state for diagnosis. See recovery.md. A retained rootfs is not
a data rollback. Recovery must never expose two copies of one Tailscale identity.
