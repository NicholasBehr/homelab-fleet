# Backup and recovery

## Direct, quiesced Borg backups

Production backups are disabled until a real repository is enrolled. Each service
gets its own restricted Storage Box subaccount, repository, SSH key and passphrase.
Obtain and independently authenticate the endpoint host key; ssh-keyscan alone is
not verification. Store the verified `[HOST]:23` entry in `/persist/borg/known_hosts`.
Hetzner's Borg endpoint uses SSH23 and remote `borg-1.4`; confirm local/remote
compatibility with `borg --version` and `borg-job-immich version` before use.

Configure the deployment with `homelab.backup.enable = true`, an actual repository
such as `ssh://SUBACCOUNT@HOST:23/./immich`, and a staggered schedule. Values shown
are placeholders. No endpoint or master credentials are invented. Initialize only
the intended new repository with `borg-job-immich init --encryption=repokey-blake2`;
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
If backup fails, abort replacement and recover services. Present exact commands
for the identified instance before this operation.

## Complete disaster restoration — still requires rehearsal

Restore to fresh, explicitly recorded test volumes first. Retain the source backup
and original volumes. Never extract over running state. Select an explicit archive
and the exact compatible image, PostgreSQL and extensions from its version record.

1. Provision bootstrap with new empty declared mounts and their markers. Establish
   a new age identity; use independently escrowed recovery credentials to decrypt
   and re-encrypt SOPS for the new identity. Retrieve compatible Borg credentials
   and verified host trust into protected runtime files; never put values in shell
   arguments or Nix. Publish/verify matching ciphertext-bearing recovery image.
2. Restore Borg into protected scratch space with enough capacity. Inspect paths
   before extraction, then put `persist/immich` on NVMe and `data/immich` on the bulk
   volume, preserving metadata. Preserve all six `.immich` markers. Validate the
   upload/library links against the chosen layout. Do not restore the old outer
   volume identity markers over newly recorded mounts.
3. Restore fixed ownership for Immich1100, PostgreSQL71 and Redis1101 as required
   by the reviewed contract. Restore Redis from the quiesced copy. Restore Borg
   config/trust separately; cache is reproducible. Keep the newly enrolled age key.
4. Restore Tailscale identity only when the original is definitively stopped or
   revoked; otherwise enroll a new node. Never duplicate a live identity.
5. Replace bootstrap root with the matching recovery image. It starts PostgreSQL
   and required extensions, with application/ML/Serve automatic startup disabled
   and backup disabled. Check they are actually inactive before DB restoration.
6. With a fresh database and app never started, inspect `pg_restore --list` on the
   custom dump. Exclude extension and public-schema creation entries already owned
   by NixOS setup. Review the resulting list for these exact extension versions.
   Restore using `pg_restore --single-transaction --exit-on-error --no-owner
   --no-privileges --role=immich --use-list=REVIEWED_LIST --dbname=immich DUMP`
   as postgres. Stop on every error; never initialize an empty replacement library.
7. Verify database rows/extensions, original checksums, layout, identity and secret
   permissions. Explicitly start ML/server/Serve and test real login, thumbnails,
   playback, search and QSV. Take a new successful backup before normal operation.

This custom-format dump uses pg_restore, not Immich's `.sql.gz` UI import. The design
follows upstream's requirement to preserve database and media together while writes
are stopped: https://docs.immich.app/administration/backup-and-restore/ . Native
NixOS paths replace Docker paths. A logical-DB scratch restore is not proof of this
entire fresh-volume procedure. Record its successful rehearsal before production.

## Other failures

Use authenticated Proxmox `pct enter ID` if Tailscale fails. Inspect mounts/markers,
free space, individual units and bounded logs without exposing secrets. Do not open
LAN ports. Never repair unknown storage by writing a marker or creating an empty DB.
For lost root with intact volumes, verify and replace root using the normal stopped
transfer procedure. After migrations, software rollback is not data rollback:
restore the pre-update backup with matching software onto fresh mounts.
