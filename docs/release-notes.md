# v0.4.1 — enforce the activation boundary

Prevent the upstream Home Assistant and PostgreSQL targets from starting services
before the root-local operational activation record is created. Extend lifecycle
wiring checks to catch enabled targets that directly start managed services.
Storage paths, credentials and application versions remain unchanged. Replace
roots only after a consistent backup and the usual identity-exclusivity checks.

# v0.4.0 — single service images and runtime credentials

Publish only `immich` and `home-assistant`; remove bootstrap/recovery outputs from
the new catalog. Each image defaults to an inactive workload. Operators use
`homelab-activate` after enrollment or isolated
restoration. Enablement lives on the disposable root and is outside Borg backups;
new roots remain inactive even with restored persistent state. The manifest marks
`variant=single`, `activationTarget` and `defaultActivated=false`. Historical
artifacts remain available for historical backups. See `docs/lifecycle.md` for
activation, shutdown and the tested NixOS root-local activation gate.

Immich and Home Assistant now read Borg credentials from root-only files at
`/persist/secrets/{borg-passphrase,borg-ssh-key}`. Images contain credential paths
and validation rules only; SOPS, age enrollment and production ciphertext leave
the current source/image inputs. Readiness rejects missing, empty, symlinked,
incorrectly owned or overly permissive files. Credential rotation no longer
requires an image release. The release manifest retains
`encryptedSecretsIncluded=false` and adds `runtimeCredentialFiles`.

Standardize one complete JSON 1Password Borg recovery Document per service,
independently retrieved and checked against SSH, endpoint trust, repository ID
and encrypted key export. Omit the resettable enrollment password. The new schema
does not require age fields; preserve historical recovery material during migration.

The Home Assistant LXC may use DHCP on the trusted LAN. Operator access remains
stable through its tagged Tailscale identity; ZHA initiates its connection to the
MR4U. Keep the coordinator socket whitelist off and do not forward the MR4U's
management or coordinator ports. This removes MAC/IP reservation coupling from
container replacement without exposing Home Assistant on the physical LAN.

Migration: before replacing an existing SOPS-based root, take a consistent backup,
preserve the old image and age recovery material, and securely enroll the same
current credentials into the new `/persist/secrets` files. Verify file contents,
ownership, permissions and independent escrow access before stopped root replacement.
Do not initialize a new Immich repository or change its credentials as part of this
migration. Follow the detailed transition in `docs/recovery.md`. Home Assistant
enrollment requires its separately enrolled credentials and verified Borg endpoint.
Complete backup and fresh-volume restoration before normal operation. Storage
markers, application state paths and ownership stay unchanged; the changed secret
requirements intentionally advance repository SemVer to 0.4.0. Database and
Zigbee-network rollback safety remain independent of the repository version.

# v0.3.0 — Home Assistant Zigbee service

Add native Home Assistant Core image variants with ZHA and SMLIGHT integrations.
The service has a single guarded `/persist` volume, loopback HTTP behind Tailscale
Serve, and a quiesced Borg backup plan. Its contract proposes 2 cores, 4 GiB RAM,
32 GiB root and 32 GiB persist; allocations remain operator reviewed. The MR4U's
CC2674P10 radio on port 7638 is the planned ZHA coordinator. The EFR32MG26 radio
remains uncommissioned for possible future Thread use.

Migration: this is a new service with no existing Home Assistant state. Before
operational enrollment, prepare a separate SOPS payload, Tailscale identity,
remote Borg repository and authenticated host key. Create and verify a fresh
`/persist` volume with marker `homelab-home-assistant-persist-v1`. Keep firmware
updates manual, create a ZHA network backup before radio changes, and rehearse
complete HA and coordinator restoration before relying on this service. Repository
SemVer does not imply database or Zigbee-network rollback safety.

# v0.2.2 — dependency refresh

Update the pinned NixOS package set and sops-nix, and advance the separate Immich
package input. The operational image contains Immich 3.3.6, Tailscale 1.104.5
and PostgreSQL 17.11. Immich 3.3.6 disables ONNX Runtime telemetry; Tailscale
1.104.5 fixes SSH and Serve connectivity stalls. CI validates uncompressed LXC
tarballs; release assets remain compressed and are validated after packaging.

The image names, storage contract v2, persistent paths, ownership and secret
requirements are unchanged. Replace the root only after a consistent backup and
verify Tailscale Serve, Immich, media playback and the next Borg backup. Do not
assume an older image can safely use a database after an application migration.

# v0.2.1 — reliable IPv4 Storage Box transport

Force the Borg SSH transport to IPv4. The production LXC has IPv4 egress but no
routed IPv6; retaining the Storage Box DNS name while selecting IPv4 avoids an
IPv6-first connection failure. Strict host-key verification and all v0.2.0 backup
and storage contracts remain unchanged.

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
