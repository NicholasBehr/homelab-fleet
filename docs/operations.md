# Operator workflow

## Build and release

Use a short-lived branch and PR; require `Required checks` before merging. GitHub
always runs lint, evaluation and shared/application fixtures. `scripts/ci-plan`
compares current image/check derivation paths with the PR base or previous main
commit. Changed/new outputs build; unavailable base builds all. Shared validation/checks run
once, then changed images build on separate runners with at most three concurrent
jobs. One always-running `Required checks` gate fails if validation or any selected
image fails/cancels; an empty image selection deliberately skips the matrix. Current evaluation
errors fail. Docs and repository version are not embedded in image derivations.

Nix's ordinary public substitutes plus a pinned GitHub Nix-store cache reuse build
results. Main validation/image jobs write default-branch caches. Same-repository PRs also
write their isolated merge-ref caches, allowing image jobs to reuse validation
outputs. Fork PRs and releases only restore. GitHub prevents main/other PRs from
restoring these PR-scoped caches: https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching .
Validation and individual images use separate keys, avoiding concurrent cache writers.
Image jobs prefer their own previous cache (including the uncompressed CI archive), then fall back
to shared validation outputs; Nix rebuilds any changed or missing derivations.
Image/check outputs have GC roots while the job runs. Cache preparation reuses
output paths from the planner rather than repeating Nix evaluation. Caches are disposable: misses
rebuild; cache availability is not proof of validation. Size limits and eviction may
reduce the speedup. Initial custom builds and changed root assembly still cost
time. Unchanged images need not be rebuilt for every service change.

Update `VERSION` and release notes on the PR. After exact-main Checks succeed,
manually dispatch Release. It rejects an already used tag/version, requests all
catalog images (reusing cached closures when available), compresses and validates
them in parallel using the same per-image job/cache pattern as CI, then validates
the exact commit, complete catalog and per-image checksums before consolidating the
release and attesting every asset. Publication waits for every image; partial releases
are refused. A repository release may
contain multiple independently deployable service images. Never overwrite assets
or use `latest` for deployment. Application versions remain independent of repo SemVer.

Before importing, verify tag commit, all asset attestations, checksum and manifest:
repository `NicholasBehr/homelab-fleet`, signer workflow `.github/workflows/release.yml`,
exact source/signer commit and `refs/heads/main`, and deny self-hosted runners.
Use `gh attestation verify ASSET --repo NicholasBehr/homelab-fleet
--signer-workflow NicholasBehr/homelab-fleet/.github/workflows/release.yml
--signer-digest COMMIT --source-digest COMMIT --source-ref refs/heads/main
--deny-self-hosted-runners`. Run `sha256sum -c SHA256SUMS` (or `shasum -a 256 -c`
on macOS). Compare service/variant, upstream versions, contract, encrypted-secret
classification, runtime credential paths, disabled activation default and expected
archive. Preserve a private verification receipt. Each service publishes one image;
see [explicit activation](lifecycle.md) for all lifecycle phases.

## Initial enrollment

Production allocations, host mutations and shared infrastructure changes require
explicit approval of a detailed execution plan under `AGENTS.md`, rather than
individual commands. The plan identifies exact resources, ordered changes,
data/credential effects, downtime, risks, recovery protection and verification.
Command-level adjustments and equivalent fixes within those approved boundaries
do not need another approval; expanded scope or uncertain provenance does.
Read-only discovery is permitted. Designated test mutations
require exact creation provenance and current GUID/attachment checks; IDs/names
alone are insufficient. Record a new allocation plan and absence checks before
creation, then immediately record its actual GUID. Never use stale public inventories.

The contract proposes CT200/201, 2 cores, 6GiB RAM, 32GiB root, 128GiB persist and
512GiB data on local-zfs. The persist allowance budgets roughly 20% of a full
originals volume for generated media, plus database, dumps, Borg cache and headroom;
it is an estimate, not a limit on application growth. Verify actual allocations in
the private operator inventory. Production provisioning, including `nesting=1`,
must be included in the approved plan. Standard native provisioning is `pct create`
with a verified local template,
`--ostype nixos --unprivileged 1`, reviewed resource/network/device options and
`--onboot 0` until validation. Downloading to the host template cache is a host write
and must be included in the approved plan.

Create only new, explicitly identified state volumes. Record GUIDs and initialize
`.homelab-volume` markers from the reviewed contract on those fresh volumes only.
Attach persist as mp0 and data as mp1; never write a marker to unidentified storage.
Proxmox mountpoints precede guest init. Verify generated AppArmor, ID maps, render
ownership, TUN0600 and all guard failures before enrolling.

Boot the service image without its root-local operational activation record and enroll unique Borg credentials through authenticated operator
access. Install `/persist/secrets/borg-passphrase` and `borg-ssh-key` as root:root
mode0600 under a root:root mode0700 directory. The image only declares paths and
validation rules. Keep all credential contents out of Git, command arguments,
logs, images and the Nix store; never promote rehearsal credentials to production.

Escrow the complete Borg recovery set as one `borg-<service-slug>` 1Password Document
in the `Homelab` vault with the `homelab` tag;
retrieve it and prove repository access and restoration before removing temporary
local copies. Never put recovery secrets on automatically disposable test volumes.
Treat the resettable Storage Box password as enrollment-only and omit it from
escrow. Enroll Tailscale interactively
with the intended service tag, approve the device, and verify checked admin SSH,
HTTPS and denied cross-service/LAN access. Policies belong to the operator; CI has
no tailnet or Proxmox credentials. Configure remote Borg as [recovery](recovery.md)
describes before trusting production data.

After enrollment, independently verified escrow and restoration checks, activate
with `homelab-activate` from the console. A fresh
root always requires this explicit step; see [lifecycle](lifecycle.md).

## Replace a root

1. Verify explicit image release and compatible versions; review migrations.
2. Identify exact old root and persistent GUIDs using creation/transfer records;
   inspect every cluster LXC/QEMU attachment. Keep retained recovery data protected.
3. Create and verify a consistent backup. For a migration-bearing replacement,
   keep the application stopped after its final backup; no writes after that point.
4. Create a fresh root on a new approved CT ID; record its GUID. Stop the old
   container gracefully. Ensure both old/new are stopped before moving mp0/mp1
   using `pct move-volume OLD mp0 --target-vmid NEW --target-volume mp0` and mp1.
5. Recheck transferred GUIDs and start NEW with its activation record absent.
   Complete offline validation, confirm the original identity is stopped, then
   explicitly enable/start the target. Check each required unit, secret
   permissions, identity continuity, DB/assets, placement, HTTPS, playback and jobs.
6. Retain old root and backup until verified. Never run two copies of one identity.
   Do not transfer migrated data back to older software without proven compatibility;
   restore the matching backup into fresh volumes instead.

Host cleanup is a separate provenance-checked batch. Never delete production,
retained recovery copies or sole backups. Underlying host changes need an explicitly approved, bounded execution
plan. Enable Secure Boot with local console access after read-only boot/signing
inspection; then verify ZFS, network, guest startup and QSV following reboot.
