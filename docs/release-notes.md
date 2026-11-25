# v0.6.5 — wait for restored identity readiness

Wait up to 30 seconds for a restored Tailscale identity to reach its Running
backend state before applying the service's no-SSH and Serve policy. This closes
the boot and backup-recovery race where `tailscaled.service` was active before
its local API was ready, causing an otherwise successful workload or Borg job to
fail and rely on a later policy retry.

Declare glibc's `getent` output in the Jellyfin directory guard's service path.
The guard can now validate existing persistent ownership after root replacement
instead of failing before Jellyfin starts.

The shared Tailscale module changes every service image, while the directory
guard change is Jellyfin-specific. Persistent paths, storage markers, identities,
credentials and contract versions remain compatible with disposable-root
replacement. The repository version advances and CI must rebuild affected images.

# v0.6.4 — repair Jellyfin first start and backup recovery

Allow Jellyfin's confined pre-start helper to seed its loopback-only network
configuration without requesting an unnecessary ownership change when it already
runs as the target user and group. This restores unattended first start under the
service's existing `PrivateUsers` and capability restrictions.

Keep the Jellyfin/Tailscale/Borg and rclone readiness blocks independent during
backup recovery. The quiesce hook now records whether the rclone timer or service
was running and the cleanup hook restarts only those recorded units, while always
attempting every required Jellyfin/Tailscale restart. A core-only installation can
therefore complete Borg backups before rclone credentials are enrolled.

The image and repository version advance because the generated Jellyfin system
changes. Persistent paths, storage markers, ownership IDs, credentials and
contract version remain compatible with replacement of the disposable root.

# v0.6.3 — increase Jellyfin 4K HDR headroom

Raise the proposed Jellyfin container allocation from two to four vCPUs and from
4 GiB to 8 GiB RAM. Intel QSV remains the video acceleration path; the additional
CPU and memory capacity covers audio conversion, library work, subtitle handling
and partial-acceleration fallback during representative 4K HDR playback.
Complete the existing Jellyfin/Tailscale/Borg core gate by validating the protected
Borg repository URI and pinned Storage Box host key in addition to its passphrase
and SSH key. The independent rclone gate remains unchanged.

The generated image and manifest embed the resource contract, so the repository
version advances even though application packages, persistent paths, markers,
ownership IDs, credential requirements and storage contract version are unchanged.
Existing verified `/persist` and `/data` volumes remain compatible with a root
replacement.

Provide `/bin/bash` from the shared base module in every service image so the
authenticated Proxmox `pct enter` recovery console selects Bash, loads the NixOS
profile PATH and exposes the already linked basic operator commands. This avoids
service-specific shell workarounds; it does not enable SSH, add Python or broaden
network access. Because the shared image base changes, CI must rebuild every
service image for v0.6.3.

Disable Tailscale SSH explicitly on every service identity while retaining
Tailscale Serve. Operators authenticate to the Proxmox host with Tailscale SSH
and enter a container with `pct enter`; service containers expose no independent
SSH control plane. OpenSSH remains disabled, restored Tailscale state is forced
away from the former SSH setting, and private HTTPS routes are unchanged.

# v0.6.2 — isolate Jellyfin core and rclone readiness

Keep Jellyfin, Tailscale and Borg behind the existing core operational-readiness
gate, which now checks only the Borg runtime credentials. Add a separate rclone
readiness gate for the protected SFTP configuration and pinned host key. Missing
or invalid SFTP enrollment therefore leaves the importer and its timer inactive
without preventing the core Jellyfin service, private HTTPS identity or Borg
timer from starting.

The image and repository version advance because the generated Jellyfin system
changes. Persistent paths, markers, ownership IDs and contract version remain
unchanged; replacement may reuse the existing verified volumes. Fresh and
replacement roots still require explicit activation after core enrollment and
identity-exclusivity checks. rclone begins only after its independent enrollment
also passes.

# v0.6.1 — increase Immich CPU allocation

Raise the proposed Immich container allocation from two to four CPU cores to
match the live host configuration. No application, storage, identity, credential,
network or backup contract changes are included.

# v0.6.0 — private Paperless-ngx PDF archive

Add a native Paperless-ngx 3.5.0 single-image service from its own pinned
`nixos-unstable` input. The application, PostgreSQL 17, Redis, original PDFs,
generated PDF/A archives, thumbnails, search index and identities use one guarded
NVMe `/persist` volume; there is no `/data` split, container runtime, public
listener, Tika/Gotenberg or AI integration.

Fresh instances require the manual `paperless-initialize` workflow and interactive
administrator creation. Normal activation refuses missing application or database
state, suppresses upstream multi-user startup and runs migrations only behind the
root-local operational activation boundary. A protected runtime file supplies the
private HTTPS origin required for proxy host and CSRF validation. Quiesced Borg backups use an atomic
logical PostgreSQL dump and retain the application offline for the entire archive
operation. Evaluated configuration, failure-injection hooks and a synthetic
Paperless/PostgreSQL/Borg restoration fixture cover the service contract.

This adds the `paperless-ngx` image and contract version 1. Existing services and
volumes are unchanged. Production allocation, credential enrollment, release
verification and full Proxmox restoration remain separate operator-approved work.

# v0.5.7 — private Jellyfin media service

Add Jellyfin as a single-image, unprivileged LXC service with its database,
configuration, metadata, thumbnails, cache and transcodes on guarded `/persist`.
Bulk movies and TV originals plus rclone staging use a separate proposed 10 TiB
`/data` HDD volume, which is deliberately excluded from Borg backups.

Expose Jellyfin only through its loopback listener and dedicated Tailscale Serve
identity. Configure Intel QSV for the planned i5-14500 UHD Graphics 770 through
the standard render-device sharing module, enabling AV1 decode but not assuming
AV1 encoding.
Use rclone's SFTP subsystem to poll remote `movies` and `tv` trees every five
minutes, copy into staging, and publish without overwriting existing files or
propagating source deletions. Require pinned SFTP host keys and protected runtime
credentials; `shell_type = none` and disabled hash probing avoid remote shell
commands.

Add Jellyfin-specific network binding, import promotion, backup failure-recovery
and configuration checks. The new image requires a patch SemVer bump. Existing
service contracts and data paths do not change. Provisioning, credential
enrollment, first activation, QSV acceptance, backup and restoration remain
separate operator operations.

# v0.5.6 — complete the lean Home Assistant core profile

Enable persistent UI-managed automations, scripts and scenes, plus Recorder,
History, Activity and Sun without adopting Home Assistant's media-, cloud- and
discovery-heavy `default_config` bundle. Add the `isal` runtime acceleration and
let Home Assistant use the timezone selected during onboarding instead of
overriding it from the container's UTC clock. This restores the Map dashboard's
history backend and normal state recording while deliberately
excluding Google Translate TTS, Met.no, Radio Browser, Shopping List, media
sources, analytics, Home Assistant Cloud and ESPHome.

Create missing UI YAML files as owned regular files under the existing
`/persist/home-assistant` state path and refuse symlink or non-file targets. The
existing storage marker, ownership IDs, secret requirements and contract version
remain unchanged. Operators replacing an affected root must review saved
`automations.yaml` for duplicate entries created by earlier timed-out UI saves.

# v0.5.5 — harden Home Assistant service routing

Proxy the tailnet-only `/zigbee2mqtt` route to Zigbee2MQTT's matching backend
base path. Live acceptance verified the page and its relative JavaScript/CSS
asset through Tailscale Serve; no extra proxy, rewrite layer, public listener or
root-local workaround is introduced.

Use Home Assistant's public manifest as the stable readiness probe so fresh
instances remain healthy while the frontend root redirects to onboarding. Order
Home Assistant after Zigbee2MQTT without making its lifetime depend on manual
Zigbee2MQTT restarts. Document that coordinator settings need a stable IPv4 or
container-resolvable FQDN and that native backup startup is asynchronous. No
persistent path, marker, ownership, secret requirement or storage contract changes.

# v0.5.4 — simplify Home Assistant Zigbee enrollment

Remove the bespoke console enrollment command and separate network-key file.
Zigbee2MQTT now generates its key and network identifiers on first start and
keeps the resulting configuration on `/persist` across restarts. Operators
provide only the coordinator endpoint through the protected runtime settings
file. Preserve the management UI behind Tailscale Serve at `/zigbee2mqtt` and
document the distinct Home Assistant and Zigbee2MQTT pages. The Home Assistant
storage contract advances to version 4; the volume marker and state paths remain.

# v0.5.3 — Home Assistant Zigbee2MQTT

Deploy a fresh Zigbee2MQTT network on the MR4U CC2674P10 radio. The single Home
Assistant image now runs loopback-only Mosquitto and Zigbee2MQTT as
separate gated services, exposes the Zigbee2MQTT frontend only through Tailscale
Serve, and retains the EFR32MG26 radio for a later Thread design.

Add protected one-time runtime enrollment for the private coordinator endpoint,
random Zigbee network key and network identifiers. Mosquitto and Zigbee2MQTT
state live on `/persist`, and Borg quiesces and restarts the complete dependency
chain. Configuration checks and synthetic tests cover listeners, credentials,
ownership and backup failures.

This is a clean deployment on a new container and new persistent volume; no old
Home Assistant or Zigbee state is imported. Factory-reset and pair only the Hue
light and SR-ZG9002KR12-Pro switch. The Home Assistant contract advances to
version 3; the volume marker is unchanged. Production creation and radio handoff
remain a separately approved operation.

# v0.5.2 — operational handoff hardening

Make `health-check` find NixOS system tools when invoked directly through
Proxmox `pct exec`, whose default PATH omits `/run/current-system/sw/bin`.
Document the live Nextcloud enrollment and recovery lessons: robust Proxmox
metadata checks, resumable account enrollment, admin-side Tailscale identity
verification and runtime-only production credentials during disposable restore
rehearsals. The validation matrix records the completed generic acceptance and
the remaining real-client login/sync check without publishing live identifiers.

No persistent path, marker, contract, application version or credential changes.
Existing data needs no migration; replace roots normally to adopt the image fix.

# v0.5.1 — preserve Nextcloud maintenance during startup

Allow an explicitly activated Nextcloud instance to start while it is already in
operator maintenance mode. Normal setup temporarily clears maintenance for the
required `occ upgrade`, restores it afterward and retries restoration if upgrade
fails. The restoration VM now activates from maintenance mode and verifies that
HTTP remains in maintenance until the operator deliberately disables it.

# v0.5.0 — private Nextcloud MVP

Add the `nextcloud` single-image service with private Tailscale HTTPS, native
PostgreSQL/Redis, 10 GiB upload limits and the complete application data directory
on `/data`. This is a deliberate Nextcloud exception to the bulk-originals-only
rule; previews, versions and trash move with user files when this volume moves to
HDD. Configuration, PostgreSQL and identity remain on `/persist`.

Initialization is explicit and creates no accounts or bootstrap passwords.
Operators create accounts through hidden terminal prompts. A protected runtime
JSON supplies the tailnet hostname; generated images contain no live domain.
Automatic installation, app-store updates and public links are disabled. Gated
upstream directory creation, quiesced logical database/Borg backups and restoration
checks are part of the service. Read `docs/nextcloud.md` before enrollment.

This adds a new contract (version 1), image/check output and runtime settings file;
existing service contracts and persistent paths do not change. No existing data is
migrated by this release. Deployments and the first full restoration rehearsal
remain manual, separately approved operator work.

# v0.4.4 — Home Assistant readiness probe

Use the unauthenticated frontend root for Home Assistant health checks. Repeated
requests to the authenticated API could trigger the configured IP-ban threshold
and ban loopback. A pre-existing loopback ban requires an approved recovery
procedure before the new probe can pass; preserve other ban entries.

# v0.4.3 — service contracts and onboarding

Harmonize Home Assistant with Immich by giving it service-owned backup hooks,
failure-injection tests, evaluated configuration checks and a full system check.
Every service is now required to have a matching deployment, resource contract and
service check set. The example Tailscale policy covers both published services.
Contract application fields use one `application` block consistently; this advances
the Immich contract to version 3 and Home Assistant's to version 2 without changing
paths or ownership values. Updated service images include these changes.

Add a normative service-onboarding contract covering names, deployment schema,
versions, lifecycle, backups, restoration, tests, policy and operator acceptance.
Flake evaluation now rejects mismatched configuration, contract, catalog or check
registries and validates each service's common runtime wiring. Shared operations
and recovery guidance is service-neutral, with exact Immich and Home Assistant
restoration procedures in their service guides.

Remove completed credential-migration and multi-image remnants from current code
and documentation. All services use root-only `/persist/secrets` Borg credentials,
one independently verified 1Password recovery Document per service and one image
per service that is inactive by default. No persistent paths, volume markers,
ownership values, application versions or credentials change in this release.

Sanitize live coordinator addressing from public documentation and reject private
IPv4 addresses in docs. Replace roots only after a consistent backup and the usual
identity-exclusivity checks.

# v0.4.2 — Home Assistant mobile app

Include and enable the Home Assistant Mobile App integration so Companion apps
can register and connect through the existing Tailscale-only HTTPS endpoint.
Persistent paths, credentials and storage contracts remain unchanged.

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
