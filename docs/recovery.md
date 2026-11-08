# Backup and recovery

## Direct, quiesced Borg backups

The operational image enables scheduled backups; bootstrap and recovery images
do not. Enroll the repository before relying on the schedule. Each service
gets its own restricted Storage Box subaccount, repository, SSH key and passphrase.
Obtain and independently authenticate the endpoint host key; ssh-keyscan alone is
not verification. Store the verified `[HOST]:23` entry in `/persist/borg/known_hosts`.
Hetzner's Borg endpoint uses SSH23 and remote `borg-1.4`; confirm local/remote
compatibility with `borg --version` and `borg-job-immich version` before use.

The Immich deployment reads its remote repository URI from
`/persist/borg/repository`, a root-owned mode0600 file containing exactly one line,
for example `ssh://SUBACCOUNT@HOST:23/./immich`. Keep the actual endpoint in the
private operator inventory, not public Nix configuration. The job and
`borg-job-immich` wrapper read the same file as data; missing/invalid files fail
before application quiescing. This runtime option accepts only remote SSH URIs;
other deployments may instead set the static `homelab.backup.repository` option.

The schedule is 02:15 Europe/Zurich. During initial enrollment, keep the timer
stopped until repository initialization, escrow and a manual backup/restore check
pass. Initialize only the intended new repository with
`borg-job-immich init --encryption=repokey-blake2`;
normal jobs have `doInit=false`. Export its Borg key and escrow the export,
passphrase, SSH key, endpoint and trust information independently in 1Password.
Retrieve/verify escrow. Keep multiple recovery copies; a backup repository alone
is not a complete 3-2-1 strategy.

Scheduled operation acquires `/persist/operation.lock`, records restart intent,
stops Immich server/ML, atomically writes a custom-format PostgreSQL dump and
version record, and stops Redis/Tailscale. Borg reads `/persist` and `/data/immich`
directly. It excludes live PostgreSQL, Borg cache, incomplete dump files and retained legacy
staging directories from the previous workflow.
Originals are read once from their explicit `/data` path; Borg archives the hot-tree
links as links. Redis and node state are frozen. PostgreSQL remains running but
only its logical dump is archived. No duplicate media staging is required.

Services stay stopped through archive creation, checking and retention work.
Downtime can be long for the first backup or large imports. Borg postHook and
systemd ExecStopPost attempt all required restarts, including after prepare/Borg
failure. Recovery intent stays if any restart fails; inspect and intervene.
Power loss cannot run cleanup, so verify normal service startup after reboot.
Retention defaults to daily7/weekly4/monthly6; warnings fail the job. A dump needs
additional NVMe space; failed dumps must fail the backup, not yield partial success.

Run `systemctl start borgbackup-job-immich`, inspect the current invocation's
exit/result and archive timestamp, and periodically run `borg-job-immich check
--verify-data`. `health-check` requires every configured unit, API/tailnet health,
successful job status and an archive no older than36h. It deliberately fails when
backups are unconfigured. Test failure recovery on the actual container before
production. Do not infer success from an old archive or old unit result.

For a migration recovery point, stop the backup timer and wait for its active job,
take the operation lock, run the same prepare hook and archive the same declared
paths/exclusions while leaving the application stopped. Verify success, then stop
the container immediately; do not run normal cleanup/restart before replacement.
If backup fails, abort replacement and recover services. Obtain approval of a detailed plan for the identified instance, including
quiescing, archive verification, replacement, failure recovery and downtime.
Equivalent command-level fixes within that approved scope need no new approval.

## Complete disaster restoration

Restore to fresh, explicitly recorded test volumes first. Retain the source backup
and original volumes. Never extract over running state. Select an explicit archive
and the exact compatible image, PostgreSQL and extensions from its version record.

1. Provision bootstrap with new empty declared mounts and their markers. Keep
   Tailscale stopped and prevent its automatic restart while restoring identity.
   Verify its MainPID is zero. Retrieve Borg credentials and authenticated endpoint
   trust from independent escrow into protected runtime files; never put secret
   values in command arguments or Nix. Verify the repository and explicit archive
   with `borg check --verify-data` before extraction.
2. Decide whether this is loss recovery or a compromise. For loss recovery, the
   archived age key can decrypt the matching image's SOPS payload. Recover Tailscale
   identity only with the original definitively stopped; revoke it and enroll a new
   node if exclusivity cannot be assured. Never run duplicate live identities.
   For suspected compromise, rotate identities/credentials instead; establish a new
   age key, re-encrypt SOPS with independently escrowed recovery credentials, and
   publish/verify the matching ciphertext-bearing image before proceeding.
3. Inspect archive paths and capacity, then selectively extract directly into the
   empty, quiesced mounts with numeric ownership preserved. Restore `persist/immich`,
   `data/immich`, Redis, the logical dump/version record under `persist/backup`,
   Borg config/trust and the chosen identities. Do not extract the entire archive
   indiscriminately: preserve the new outer volume markers and omit live PostgreSQL,
   reproducible caches and legacy staging. Duplicate scratch media is unnecessary.
   Keep the source archive and original volumes retained.
4. Verify Immich1100, PostgreSQL71 and Redis1101 ownership against the reviewed
   contract, all six `.immich` markers (which may be empty), and upload/library links
   into `/data/immich`. Keep thumbnails, previews and encoded video on `/persist`.
   Check the restored age key is root-owned mode0600.
5. Replace bootstrap root with the matching recovery image using stopped transfers
   and GUID/attachment checks. Wait for systemd initialization to complete and verify
   storage/readiness gates, PostgreSQL and Redis individually. Automatic app/ML and
   `tailscale-policy` startup and backups are disabled in this image. Restored
   Tailscale state can still contain a saved Serve proxy: run `tailscale serve reset`
   and verify no Serve configuration and app/ML MainPID zero before DB restoration.
   Verify decrypted SOPS secrets are root-owned mode0400.
6. With a fresh database and app never started, inspect `pg_restore --list` on the
   custom dump. Exclude extension and public-schema creation entries already owned
   by NixOS setup. Review the resulting list for these exact extension versions.
   Restore using `pg_restore --single-transaction --exit-on-error --no-owner
   --no-privileges --role=immich --use-list=REVIEWED_LIST --dbname=immich DUMP`
   as postgres. Stop on every error; never initialize an empty replacement library.
7. Verify database rows/extensions, original checksums, layout, identity and secret
   permissions. Replace the recovery root with the matching operational image via
   another stopped, provenance-checked transfer. Verify normal startup, HTTPS, real
   login, thumbnails, playback and jobs; check search/QSV for the intended workload.
   Take a new successful backup and verify service/API recovery before normal use.

This custom-format dump uses pg_restore, not Immich's `.sql.gz` UI import. The design
follows upstream's requirement to preserve database and media together while writes
are stopped: https://docs.immich.app/administration/backup-and-restore/ . Native
NixOS paths replace Docker paths. The v0.1.0 rehearsal passed this fresh-volume
procedure using independent escrow and an off-guest encrypted repository, including
normal operational startup, original checksums, login/playback and a new backup.
A separate test Storage Box rehearsal also passed remote integrity/retention,
isolated media/database restoration and independent 1Password escrow retrieval.
Production subsequently passed the same remote backup, integrity, independent
escrow and isolated restoration gates; its daily timer is active. See
[validation](validation.md).

## Other failures

Use authenticated Proxmox `pct enter ID` if Tailscale fails. Inspect mounts/markers,
free space, individual units and bounded logs without exposing secrets. Do not open
LAN ports. Never repair unknown storage by writing a marker or creating an empty DB.
For lost root with intact volumes, verify and replace root using the normal stopped
transfer procedure. After migrations, software rollback is not data rollback:
restore the pre-update backup with matching software onto fresh mounts.
