# Borg backups and restoration

Production backups are **unconfigured** by default. No Storage Box hostname, key,
repository or host fingerprint is invented. Module evaluation and disposable local
Borg/PostgreSQL tests do not establish a working remote backup.

## Enrollment

Hetzner's documented Borg endpoint is SSH port 23 and named remote binary borg-1.4.
The pinned local borgbackup package must report a compatible 1.4 version: check
`borg --version`, then `borg version "$BORG_REPO"` after enrollment. Stop on mismatch.
Use a separate restricted subaccount, directory/repository and SSH key for Immich;
do not install Storage Box master credentials in a container. Enable SSH for the
subaccount via the provider console. Review subaccount isolation there.

Obtain the endpoint host key through Hetzner's authenticated console/documentation
and an independent trusted channel. `ssh-keyscan -p 23 HOST` is only a collection
tool, never proof of authenticity. Write the verified `[HOST]:23 KEYTYPE KEY` line
to `/persist/borg/known_hosts` (approved mutation) and retain a recovery copy.
Escrow endpoint/subaccount, SSH key, passphrase and exported Borg key in 1Password.

Configure explicitly in hosts/immich.nix and review/release a new image:

```nix
homelab.backup = {
  enable = true;
  repository = "ssh://ACTUAL_SUBACCOUNT@ACTUAL_HOST:23/./immich";
  remotePath = "borg-1.4";
  schedule = "*-*-* 02:15:00";
};
```

The capitalized values above are documentation placeholders, not working config.
Module options also expose paths, excludes, runtime passphrase/SSH-key/trust-file
references, retention, prepare and cleanup hooks. Never use literal secret values
in Nix. Default retention: daily7/weekly4/monthly6. Subsequent services must have
staggered schedules and their own lock/repository. The initial connection limit is
ten; no distributed scheduler is installed.

After approved enrollment, inside the container use the NixOS-provided job wrapper
`borg-job-immich` (inspect `command -v borg-job-immich` and `--help` first). It carries
the job's runtime environment and remote-path. Initialize explicitly:

```sh
borg-job-immich init --encryption=repokey-blake2
borg-job-immich key export /persist/borg/recovery-key.export
chmod 0600 /persist/borg/recovery-key.export
```

Securely import that export into 1Password before removing its local temporary
copy with approval. It is intentionally excluded from Git and image builds.
`doInit=false` prevents accidental repository creation during normal scheduled jobs.

## Consistency and staging

The preparation hook pre-copies bulk originals to `/data/.backup-stage/media`
and hot state (excluding upload/library links) to `/persist/backup/immich-hot`, pauses
Immich writes, final-syncs including deletions, dumps PostgreSQL using the actual
configured PostgreSQL package, records versions, copies stopped Redis state, then
restarts services. Borg reads the stable staged tree plus /persist, excluding live
PostgreSQL, live Redis, live /persist/immich and Borg cache. Essential media exists in exactly one Borg
path; the live and staged trees are not both traversed. Reserve sufficient /data
space for approximately TWO copies of the originals plus growth. /persist must fit
the DB and dump plus approximately TWO copies of hot state (thumbnails, encoded
video, profiles and built-in backups). Reject insufficient-space preflight. Initial copy may be long;
application downtime covers final sync and dump, not the remote upload. The dump
and media reflect the same quiesced application state. CPU ML is paused too.

The NixOS Borg EXIT hook runs cleanup on failures. ExecStopPost also attempts
recovery on systemd termination. Partial stop, final-sync and dump failures leave
a restart-intent marker; cleanup restores services. Host/power loss cannot run a
cleanup hook: normal boot starts services again. Check status after recovery.
Hook failures propagate; failOnWarnings=true means warnings block deployment.
Failures in recovery hooks require operator attention; never declare backup success
from the existence of an archive alone. Use `systemctl status borgbackup-job-immich`,
`journalctl -u borgbackup-job-immich`, `borg-job-immich list`, and periodic
`borg-job-immich check --verify-data`. A successful old Result alone is not freshness;
inspect the current invocation/exit and the archive timestamp and metadata.

## Final migration recovery point

To eliminate writes after the recovery point, stop the timer, wait for active job,
then inside an approved container console:

```sh
exec 9>/persist/operation.lock
flock -n 9
systemctl stop immich-server immich-machine-learning
# Final sync and dump while application remains stopped:
rsync -a --delete /data/immich/ /data/.backup-stage/media/
rsync -a --delete --exclude=/upload --exclude=/library /persist/immich/ /persist/backup/immich-hot/
runuser -u postgres -- pg_dump -Fc immich > /persist/backup/immich.dump.tmp
mv /persist/backup/immich.dump.tmp /persist/backup/immich.dump
cp /etc/homelab-versions.json /persist/backup/versions.json
systemctl stop redis-immich
rm -rf /persist/backup/redis
cp -a /persist/redis /persist/backup/redis
ARCHIVE="pre-replacement-$(date -u +%Y%m%dT%H%M%SZ)"
borg-job-immich create --stats "::$ARCHIVE" /persist /data/.backup-stage   --exclude /persist/postgresql --exclude /persist/redis --exclude /persist/immich --exclude /persist/borg/cache
borg-job-immich info "::$ARCHIVE"
# Only after successful create/info, immediately power off; no application restart.
systemctl poweroff
```

This conservative final archive holds the application stopped for its upload;
Borg deduplication usually makes the final upload small after the earlier backup.
Abort deployment on failure and explicitly restart redis-immich, Immich server and
ML plus the timer. Long-media normal backups use the shorter staging procedure.
A future snapshot design requires separate validation, not implied host privileges.

## Fresh-volume restore

Select the image matching archived application/DB versions. Provision bootstrap
onto new empty declared volumes using provisioning.md, but do not initialize an
operational DB or enroll a duplicate Tailscale identity. Enroll a fresh age key and
recovery-decrypt/re-encrypt SOPS as secrets.md describes. Retrieve Borg credentials
and host keys from independent escrow. Use an operator recovery shell with compatible
Borg, PostgreSQL and extensions; no plaintext in shell arguments or store.

Set BORG_REPO to the real endpoint, BORG_PASSCOMMAND to `cat /run/PROTECTED_FILE`,
and BORG_RSH to SSH with the runtime private-key path and strict known_hosts. These
variables reference files, never contain private values. Check repository and
select explicit ARCHIVE. Extract into a separate protected scratch filesystem:

```sh
mkdir -m 0700 /data/.restore
cd /data/.restore
borg extract "::$ARCHIVE"
cat persist/backup/versions.json
```

Do not extract over running state. Inspect archive paths (`borg list`) first.
On fresh volumes move the extracted staged media to `/data/immich`, preserving metadata:

```sh
# Fresh empty media target only: rmdir refuses nonempty directories.
if test -d /data/immich; then rmdir /data/immich; fi
mv data/.backup-stage/media /data/immich
chown -R 1100:1100 /data/immich
# Restore hot state onto NVMe, leaving originals only on /data.
install -d -m 0700 -o 1100 -g 1100 /persist/immich
rsync -a --exclude=/upload --exclude=/library persist/backup/immich-hot/ /persist/immich/
chown -R 1100:1100 /persist/immich
# Recovery image recreates and validates the two original-media symlinks.
```

For the quiesced Redis copy, after the recovery image has created its service user:

```sh
systemctl stop redis-immich
rsync -a /data/.restore/persist/backup/redis/ /persist/redis/
chown -R 1101:1101 /persist/redis
systemctl start redis-immich
```

The one-time restore chown is deliberate; never do this on every boot. Restore
identity files only if the original container is definitively stopped/revoked;
otherwise keep the new Tailscale identity and enroll it separately. Retain the NEW
age identity used to encrypt the new release. Restore Borg config/security state,
verified known_hosts and Redis from its quiesced copy with correct fixed ownership.
Do not copy live archived PostgreSQL (it is excluded). With the timer disabled:

```sh
rsync -a /data/.restore/persist/borg/config/ /persist/borg/config/
install -m 0600 /data/.restore/persist/borg/known_hosts /persist/borg/known_hosts
```

Keep the protected extraction directory until restore verification; later cleanup
needs separate approval. It resides on /data so media extraction cannot fill the
small /persist volume.

Publish and verify the `immich-recovery` variant from the matching reviewed commit.
It enables PostgreSQL/extensions but removes application, ML and Serve automatic
startup and disables backups. Replace the bootstrap rootfs with this recovery
image using the stopped-container volume-transfer steps in deployment.md. The
newly enrolled SOPS key/ciphertext must be present so operational-ready succeeds.
Do not use a normal operational image before the dump is restored.
Confirm `systemctl is-active immich-server immich-machine-learning` is inactive.

Start PostgreSQL with the matching extension packages and empty dataDir; NixOS
postgresql-setup creates the immich role/database/extensions. Restore as postgres:

```sh
install -m 0600 -o postgres -g postgres /data/.restore/persist/backup/immich.dump /persist/postgresql/restore.dump
pg_restore --list /persist/postgresql/restore.dump > /persist/postgresql/restore.list
# Extensions and public schema were created by postgresql-setup.
sed -i '/ EXTENSION /d; / SCHEMA - public /d; / SCHEMA public /d' /persist/postgresql/restore.list
runuser -u postgres -- pg_restore --no-owner --no-privileges --role=immich \
  --use-list=/persist/postgresql/restore.list --dbname=immich /persist/postgresql/restore.dump
```

Stop on restore errors; check the filtered list against this exact extension/schema version. Validate DB rows and media integrity. Start
application with `systemctl start immich-machine-learning immich-server tailscale-policy` only after successful restore, then verify login/assets/GPU and create
a fresh successful backup before normal replacement to the standard image.
This procedure is a reviewable recovery plan; actual Immich extension restoration
must pass the host rehearsal before production data is trusted to it.

## Reuse an existing media volume

Keep the existing media volume read-only for inspection and retain a snapshot or
backup first. Match it to the selected database recovery point. A newer media tree
is not automatically consistent with an older dump: restore staged media into a
separate directory/volume, compare, then select it with approval. Do not run rsync
--delete against the only existing media copy. Attach to only one stopped target,
verify marker/ownership and perform DB restoration as above. Never initialize an
empty library as fallback. Keep failed/current state until recovery is verified.
