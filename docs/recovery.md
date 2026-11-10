# Backup and recovery

## Direct, quiesced Borg backups

The operational image enables scheduled backups; bootstrap and recovery images
do not. Enroll the repository before relying on the schedule. Each service
gets its own restricted Storage Box subaccount, repository, SSH key and passphrase.
Obtain and independently authenticate the endpoint host key; ssh-keyscan alone is
not verification. Store the verified `[HOST]:23` entry in `/persist/borg/known_hosts`.
Hetzner's Borg endpoint uses SSH23 and remote `borg-1.4`; confirm local/remote
compatibility with `borg --version` and the service's `borg-job-<service>
--version` wrapper before use.

Use the subaccount domain (`<subaccount>.your-storagebox.de`), not the main account
domain. During enrollment, force a supported host-key algorithm and compare the
presented fingerprint with Hetzner's independently published Storage Box host keys
before accepting it. Install the public key with Hetzner's `install-ssh-key`
command so existing keys are appended in both supported formats; do not use an SCP
method that overwrites `authorized_keys`. Each service subaccount has its own
`authorized_keys`. See Hetzner's official
[Storage Box overview](https://docs.hetzner.com/storage/storage-box/general/) and
[SSH-key procedure](https://docs.hetzner.com/storage/storage-box/ssh-keys/add-ssh-keys/).

For the one-time password-authenticated key installation, disable SSH-agent and
public-key attempts (`IdentitiesOnly=yes`, `PubkeyAuthentication=no`,
`PreferredAuthentications=password`). This prevents unrelated agent keys from
exhausting the server's authentication-attempt limit. Pin the independently
verified host key in a protected temporary `known_hosts` file, then reuse that
exact entry for runtime enrollment.

The production default for Immich and Home Assistant is a normal prune-capable
Borg repository, a dedicated service subaccount and **ten daily automatic Storage
Box snapshots**. The client credentials are not append-only because their native
Borg jobs apply retention pruning. Verify the snapshot schedule and usable restore
points in the private operator record; do not infer protection from the configured
slot count alone. Service subaccounts cannot manage provider snapshots, so this
gives a ten-day deletion-recovery window after a service-container compromise and
prevents one service credential from reaching the other service's repository.

This is an explicit simplicity/security tradeoff, not immutability or a complete
3-2-1 design. A Hetzner administrator-account compromise, whole-Storage-Box loss
or cancellation, and corruption discovered after ten days remain outside that
window. Keep the administrator account strongly authenticated, alert on stale
backups within 36 hours, rehearse snapshot recovery, and add a separately
controlled third copy if those residual risks are unacceptable.

Do not add Borg's append-only restriction to the existing client key without also
changing the job and recovery procedure. An append-only design must remove client
`prune`/`compact`, keep an unrestricted maintenance identity outside every service
container, review deletion markers before maintenance writes, bound repository
growth, and rehearse recovery of archives marked deleted. Treat that as a separate
reviewed storage-contract migration. Hetzner documents the important caveat that a
restricted client can still mark archives deleted and a later unrestricted write
can finalize those deletions.

## Recovery escrow document standard

Use the same escrow flow for every production service. Create one 1Password
**Document** in the approved operator vault, named `<Service> production recovery`,
whose file is `<Service-slug>-production-recovery-enrolled.json` (for example,
`Immich-production-recovery-enrolled.json` or
`Home-Assistant-production-recovery-enrolled.json`). Do not split the material
across Login, Secure Note or attachment items. Do not put the 1Password item/vault
IDs, live account names or endpoint values in this repository.

The JSON document has this service-independent shape; strings shown below describe
the value and are not literals to copy:

```json
{
  "purpose": "service and environment",
  "borgPassphrase": "repository passphrase",
  "borgSshPrivateKey": "dedicated private SSH key",
  "borgSshPublicKey": "matching public SSH key",
  "storageBox": {
    "hostname": "authenticated endpoint",
    "username": "restricted service subaccount",
    "port": 23,
    "knownHosts": "independently authenticated [host]:23 entry",
    "repositoryInitialized": true,
    "repository": "complete private ssh repository URI",
    "repositoryID": "Borg repository ID",
    "remotePath": "borg-1.4",
    "encryptedBorgKeyExport": "borg key export --paper output",
    "schedule": "documented local schedule"
  },
  "status": "enrolled"
}
```

Generate each service's Borg SSH key and Borg passphrase separately;
never reuse Immich material. Keep working plaintext only in a mode0700 temporary
directory with private files mode0600. The Storage Box account password is an
enrollment credential, not recovery material: use it interactively to install the
dedicated public key, then rely on the escrowed SSH key. It may be reset through
the provider and is intentionally absent from the recovery document. It remains
valid at Hetzner until reset; treating it as single-use is an operator convention,
not automatic revocation. Do not grant the service access to provider credentials.

Follow `AGENTS.md` secret-handling rules throughout enrollment and recovery. Set
umask077 before file creation; metadata and success/failure results are sufficient
for agent inspection. Secret values must travel directly between protected files,
trusted programs and the intended endpoints, never through chat, clipboard, shell
arguments, environment values or tool output. Disable tracing and payload logging;
ensure errors cannot echo secrets. Compare files silently rather than displaying
contents or hashes. Create runtime credentials through protected staging and
atomic installation that refuses existing targets. Changes to existing credentials
follow the reviewed rotation plan. Use synthetic material for CI and tests.

Write the final document only after the intended repository is initialized and its
ID and encrypted key export are available. Download the saved Document again into
a fresh protected directory and verify, without trusting the working copy, that:

1. the SSH public key derives from `borgSshPrivateKey` and authenticates only the
   restricted service subaccount;
2. `knownHosts` matches the independently authenticated endpoint key;
3. the repository opens with `borgPassphrase`, its ID matches `repositoryID`, and
   the encrypted key export is usable with the documented passphrase; and
4. repository, remote path and schedule match the deployed runtime files and job.

Set `status` to `enrolled` and enable scheduled backups only after these checks and
a fresh-volume restore rehearsal pass. Then remove the protected working plaintext
and retain the independently retrieved Document. Rotation replaces all affected
runtime credentials and the escrow document as one reviewed
operation; never assume an old document remains compatible.

## Runtime credential contract and migration

Images declare credential paths and validation rules only. Each service keeps
`/persist/secrets` root:root mode0700 and its `borg-passphrase` and `borg-ssh-key`
files root:root mode0600 (mode0400 is also accepted). Missing, empty, symlinked,
incorrectly owned or overly permissive credentials fail readiness. Files and their
parent directories must not be writable by other users. Never repair unsafe files
by silently replacing them. All `/persist` credentials are included in encrypted
Borg archives; independent 1Password recovery access breaks the bootstrap cycle.

One Borg Document is the sole service backup recovery secret record. It replaces
age identities and loose key attachments for new enrollments. Application logins,
radio passwords and provider administrator access remain separate credentials;
the Borg Document does not replace those operator accounts.

Before replacing a pre-v0.4.0 SOPS-based root, take a consistent backup and preserve
the exact old image, ciphertext and age recovery material. With the existing root
still available, securely install the current `/run/secrets/borg-passphrase` and
`borg-ssh-key` contents at the new `/persist/secrets` paths without displaying them,
changing their values or overwriting existing destination files. Compare file
contents privately and validate ownership/modes. Verify the unchanged repository
ID and key export using a fresh download of the service's 1Password Document.
Stop if destination files conflict or independent recovery cannot be proved.

Replace only the root through the approved stopped-transfer procedure; verify
startup, backup, independent recovery and fresh-volume restoration. Preserve old
age identities and the original recovery Document until these checks pass; older
images and historical archives may still need them. Do not rewrite Git history or
assume removing current ciphertext invalidates old copies. No application data,
repository encryption, database schema or volume marker changes are implied.

The Immich deployment reads its remote repository URI from
`/persist/borg/repository`, a root-owned mode0600 file containing exactly one line,
for example `ssh://SUBACCOUNT@HOST:23/./immich`. Keep the actual endpoint in the
private operator inventory, not public Nix configuration. The job and
`borg-job-immich` wrapper read the same file as data; missing/invalid files fail
before application quiescing. This runtime option accepts only remote SSH URIs;
other deployments may instead set the static `homelab.backup.repository` option.

Immich's schedule is 02:15 Europe/Zurich. During initial enrollment, keep the timer
stopped until repository initialization, escrow and a manual backup/restore check
pass. Initialize only the intended new repository with
`borg-job-immich init --encryption=repokey-blake2`;
normal jobs have `doInit=false`. Export its Borg key and escrow the export,
passphrase, SSH key, endpoint and trust information in the standard 1Password
Document above. Retrieve and verify that document independently. Keep multiple
recovery copies; a backup repository alone is not a complete 3-2-1 strategy.

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
   archived runtime credentials can be restored directly. Recover Tailscale
   identity only with the original definitively stopped; revoke it and enroll a new
   node if exclusivity cannot be assured. Never run duplicate live identities.
   For suspected compromise, rotate identities/credentials instead; establish a new
   runtime credential set and update independent escrow before proceeding. If the
   Borg encryption key was exposed, changing its passphrase alone is insufficient;
   plan a new repository and credential rotation.
3. Inspect archive paths and capacity, then selectively extract directly into the
   empty, quiesced mounts with numeric ownership preserved. Restore `persist/immich`,
   `data/immich`, Redis, the logical dump/version record under `persist/backup`,
   Borg config/trust, `persist/secrets` and the chosen identities. Do not extract the entire archive
   indiscriminately: preserve the new outer volume markers and omit live PostgreSQL,
   reproducible caches and legacy staging. Duplicate scratch media is unnecessary.
   Keep the source archive and original volumes retained.
4. Verify Immich1100, PostgreSQL71 and Redis1101 ownership against the reviewed
   contract, all six `.immich` markers (which may be empty), and upload/library links
   into `/data/immich`. Keep thumbnails, previews and encoded video on `/persist`.
   Check restored runtime credentials are root:root mode0600 under mode0700.
5. Replace bootstrap root with the matching recovery image using stopped transfers
   and GUID/attachment checks. Wait for systemd initialization to complete and verify
   storage/readiness gates, PostgreSQL and Redis individually. Automatic app/ML and
   `tailscale-policy` startup and backups are disabled in this image. Restored
   Tailscale state can still contain a saved Serve proxy: run `tailscale serve reset`
   and verify no Serve configuration and app/ML MainPID zero before DB restoration.
   Verify restored runtime credentials pass the readiness gate.
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
