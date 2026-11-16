# Backup and recovery

## Direct, quiesced Borg backups

The single service image has no root-local operational activation record by default.
Explicit activation starts scheduled backups; enrollment and restoration use the
same image with the target inactive. See [lifecycle](lifecycle.md). Enroll the
repository before relying on the schedule. Each service
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
**Document** in the `Homelab` vault, titled `borg-<service-slug>` and tagged
`homelab`. For example, the Immich and Home Assistant item titles are
`borg-immich` and `borg-home-assistant`. The Document's attached JSON filename is
informational; use `<service-slug>-production-recovery-enrolled.json`. The JSON
`status` must be `enrolled` after independent verification. Do not split the
material across Login, Secure Note or attachment items. Do not put 1Password
item/vault IDs, live account names or endpoint values in this repository.

For recovery, identify the service slug from its deployment contract, then retrieve
the exact `borg-<service-slug>` Document from `Homelab` into a new, protected file.
For example, after creating a private mode0700 staging directory and setting
`umask 077`:

```sh
op document get borg-immich --vault Homelab --out-file /path/to/new-private-file.json
```

Replace the placeholder with a fresh path; do not print the Document, enumerate
unrelated items, use a clipboard, or overwrite an existing file. Inspect its schema
and compare credentials only through status-only verification as described below.
The same title and vault convention applies to future services.

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

Set `status` to `enrolled` only after these checks. Before enabling scheduled
backups, complete a fresh-volume restore rehearsal. For a new empty repository,
rehearse the same image and procedure with synthetic data and a separate disposable
repository and volumes; an empty production repository has no archive to restore.
Then remove the protected working plaintext
and retain the independently retrieved Document. Rotation replaces all affected
runtime credentials and the escrow document as one reviewed
operation; never assume an old document remains compatible.

## Runtime credential contract

Images declare credential paths and validation rules only. Each service keeps
`/persist/secrets` root:root mode0700 and its `borg-passphrase` and `borg-ssh-key`
files root:root mode0600 (mode0400 is also accepted). Missing, empty, symlinked,
incorrectly owned or overly permissive credentials fail readiness. Files and their
parent directories must not be writable by other users. Never repair unsafe files
by silently replacing them. All `/persist` credentials are included in encrypted
Borg archives; independent 1Password recovery access prevents dependence on the
lost volume.

One Borg Document is the sole service backup recovery secret record. Application
logins, radio passwords and provider administrator access remain separate
credentials; the Borg Document does not replace those operator accounts.

Every production deployment reads its remote repository URI from
`/persist/borg/repository`, a root-owned mode0600 file containing exactly one remote
SSH URI. Keep the endpoint in the private operator inventory, not public Nix. The
native job and `borg-job-<service-slug>` wrapper read the same data file;
missing/invalid files fail before application quiescing. Static repository options
are for isolated fixtures, not production endpoint publication.

During initial enrollment, keep the target inactive until repository initialization,
independent escrow verification and an isolated synthetic backup/restore rehearsal
pass. Initialize only the intended new repository with the service wrapper and
`--encryption=repokey-blake2`; normal jobs have `doInit=false`. Export the Borg key
and escrow it with the passphrase, SSH key, endpoint and trust information. After
activation, run the native job immediately and independently restore representative
data before treating the service as protected. Do not add irreplaceable data before
that point. A backup repository alone is not a complete 3-2-1 strategy.

Scheduled operation acquires `/persist/operation.lock`, records restart intent and
runs the service's prepare hook before Borg reads its declared paths. Services stay
stopped through archive creation, checking and retention work. The post-hook and
systemd `ExecStopPost` attempt cleanup after prepare/Borg failure; recovery intent
stays if cleanup fails. Power loss cannot run cleanup, so verify service state after
reboot. Warnings fail the job. `health-check` requires declared units, API/tailnet
health, a successful job and a fresh archive; it deliberately fails when backups
are unconfigured. Exact schedules, paths, exclusions and quiescing behavior belong
in each service guide.

For a migration recovery point, stop the backup timer and wait for its active job,
take the operation lock, run the same prepare hook and archive the same declared
paths/exclusions while leaving the application stopped. Verify success, then stop
the container immediately; do not run normal cleanup/restart before replacement.
If backup fails, abort replacement and recover services. Obtain approval of a
detailed plan for the identified instance, including quiescing, archive
verification, replacement, failure recovery and downtime.
Equivalent command-level fixes within that approved scope need no new approval.

## Complete disaster restoration contract

Every service follows this outer sequence; its service guide supplies exact archive
paths, ownership, logical restore commands and acceptance checks.

1. Select an explicit verified archive and the exact compatible image from its
   manifest/version record. Restore first to fresh volumes whose creation records,
   paths and markers match the reviewed contract. Retain the source archive and
   original volumes; never extract over running state.
2. Confirm the replacement root has no activation record, the operational target
   is inactive and Tailscale plus all application units have no running process.
   Retrieve only the intended service's Borg Document from `Homelab` into protected
   storage and verify repository/archive integrity before extraction.
3. Decide whether identities may be restored or must be rotated. Never start a
   restored Tailscale, application, database or coordinator identity while its
   original may still run. A compromise recovery requires a reviewed credential,
   repository and identity-rotation plan.
4. Inspect archive paths and capacity, then selectively extract the service guide's
   allowlisted paths with numeric ownership preserved. Preserve new outer volume
   markers; omit live database files, reproducible caches and disposable root state.
5. Verify fixed ownership, internal application markers/links, credential modes,
   checksums and declared volume placement. Initialize no empty replacement state
   and stop on any incompatible or unexplained path.
6. Start only the explicitly documented restoration helpers while the operational
   target remains inactive. Perform the service-specific logical restore, verify
   its data and stop every helper again. Keep Tailscale and application listeners
   stopped throughout this phase.
7. Establish identity exclusivity, run the service acceptance checks, then activate
   this same root with `homelab-activate`. Verify real workload behavior, take a new
   backup and independently restore representative data before normal use.

A new service is incomplete until `docs/<service-slug>.md` defines the selective
paths, exclusions, owners, restoration helpers, logical restore, integrity checks,
identity rules and acceptance tests required by this sequence.

Immich's exact paths, PostgreSQL procedure, ownership and acceptance checks are in
the [Immich service guide](immich.md). Home Assistant's SQLite/Zigbee procedure is
in the [Home Assistant service guide](home-assistant.md).

## Other failures

Use authenticated Proxmox `pct enter ID` if Tailscale fails. Inspect mounts/markers,
free space, individual units and bounded logs without exposing secrets. Do not open
LAN ports. Never repair unknown storage by writing a marker or creating an empty DB.
For lost root with intact volumes, verify and replace root using the normal stopped
transfer procedure. After migrations, software rollback is not data rollback:
restore the pre-update backup with matching software onto fresh mounts.
