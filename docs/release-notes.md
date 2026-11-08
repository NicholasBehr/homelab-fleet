# v0.2.0 — production enrollment and scheduled backup

Production ciphertext replaces disposable rehearsal credentials. Resource defaults
are 2 cores, 6GiB RAM, 32GiB root, 128GiB persist and 512GiB data, with no swap.
The operational image enables the native Borg job at 02:15 Europe/Zurich; bootstrap
and recovery images keep it disabled. Application versions and storage markers/UIDs
are unchanged.

Migration: before operational use, enroll the new production age identity and
verified secrets, install root-owned mode0600 `/persist/borg/repository` containing
one remote SSH URI, and install verified `/persist/borg/known_hosts`. Initialize
only an explicitly approved new repository, export/escrow its key, and prove a
manual backup and restoration before enabling unattended operation. Keep the timer
stopped during enrollment. Missing/invalid endpoint files fail before quiescing
services; there is no automatic repository initialization. Existing rehearsal
identities cannot decrypt the new production payload. Retain matching images and
recovery material for rehearsal restoration; do not replace their roots with this
production release.

The new runtime file is an operator-managed enrollment input backed up under
`/persist`. Account identifiers remain outside public Git and image inputs. Release
publication and deployment are separate reviewed operations.

# v0.1.0 — initial repository interface

Refactors shared NixOS/LXC, storage, secret, network and Borg infrastructure away
from Immich-specific configuration, patches and hooks. Images remain native,
unprivileged NixOS LXC roots. Existing persistent paths, marker values and UID/GID
assignments are retained; storage contract remains v2.

Backups now keep services stopped for the full Borg operation and read media directly.
No duplicate media staging is required. Old staging directories on existing test
volumes are retained until a separately verified cleanup; they are excluded from
the direct source paths. Historical staged archives require their historical restore
layout, not the new direct-archive instructions. There are no production archives yet.

Checks select changed evaluated derivations and reuse GitHub Nix-store caches.
Images run on separate runners, capped at three parallel jobs, after shared
validation. The stable required gate handles failures and empty selections. Releases
use the same parallel image job and validate the complete artifact handoff before
publication.
Unavailable comparison builds all. Repository releases include catalog images under
one SemVer tag, separate from upstream application versions. Manifests retain commit,
contract, build output and upstream versions; every asset is attested.

The compatibility interface includes flake image names, manifests, deployment
contracts, persistent paths/markers, UID/GID assignments, required secrets and recovery
procedures. Incompatible changes require explicit migration notes and an appropriate
version increase. Pre-1.0 interfaces are still evolving. Never modify a published tag
or release. A compatible version number does not prove database rollback safety.

Rehearsal-only encrypted credentials remain; this is not production enrollment.
See validation.md for completed checks and outstanding production gates.
