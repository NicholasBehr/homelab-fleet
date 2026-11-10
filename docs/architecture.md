# Architecture

## Code boundaries

`modules/` implements shared base hardening, native Proxmox LXC integration,
mount-identity guards, runtime credential readiness, Tailscale, optional Intel userspace and Borg.
Modules declare options and never import service deployments. `services/immich/`
owns native application settings, hot/bulk layout, package patch, backup hooks and
service tests. `deployments/immich.nix` explicitly composes modules and supplies
storage, secret and endpoint settings. Its adjacent contract records proposed
resources and fixed ownership. `lib/mk-container.nix` constructs systems; the flake
explicitly registers configurations, images, contracts and checks.

NixOS 26.05 is pinned in `flake.lock`. Immich's module/package use a separate
pinned unstable input because the stable package was marked insecure. PostgreSQL
17 remains stable. `system.stateVersion` stays 26.05; it is not an upgrade switch.
Review both pins, migration notes and extension versions before updates.

## Image and runtime

GitHub builds NixOS's native Proxmox LXC root tarball using bounded pixz compression.
Proxmox imports that userspace; the container shares the host kernel and boots
systemd through `/sbin/init`. No Docker daemon, guest kernel or guest bootloader.
Root is disposable by replacement policy, not wiped each boot; no impermanence module.
Software is in `/nix/store`, declarative config is exposed under `/etc`, temporary
runtime state is under `/run`. No runtime keys or data-volume contents ship in images.
Credentials are enrolled on `/persist` independently of image builds. Neither
plaintext nor encrypted production credential payloads enter image inputs.

Unprivileged default UID mapping, generated AppArmor confinement and test-validated
`nesting=1` remain. No privileged LXC, unconfined profile, DKMS, VF or kernel changes.
Render sharing uses `/dev/dri/renderD128` with fixed guest render GID303; TUN is0600.
Native `ostype=nixos` and `manageNetwork=false` let Proxmox supply networking.
Tailscale provides checked SSH and HTTPS Serve; ordinary sshd is disabled. App and
ML bind loopback. The firewall exposes no application ports to the physical LAN.

## Home Assistant files

Home Assistant Core runs as the upstream NixOS service in its own unprivileged
LXC. It binds HTTP to `127.0.0.1:8123` and is exposed only through Tailscale Serve.
ZHA owns the Zigbee network and connects to the SLZB-MR4U over wired LAN TCP. The
SMLIGHT integration separately provides coordinator monitoring and management.
This deployment has no USB, render device, Thread, OTBR, MQTT broker or `/data`.

| Path | Purpose |
|---|---|
| `/persist/home-assistant` | SQLite database, `.storage`, ZHA configuration/network backups, automations and dashboards |
| `/persist/home-assistant/backups` | Home Assistant backup artifacts |
| `/persist/tailscale` | Tailnet identity and Serve state |
| `/persist/secrets/{borg-passphrase,borg-ssh-key}` | Operator-enrolled root-only Borg credentials |
| `/persist/borg/{config,cache,known_hosts}` | Borg configuration, disposable cache and authenticated SSH trust |
| `/persist/borg/repository` | Private runtime repository URI |

The single `/persist` volume is guarded by its exact marker before HA or Tailscale
starts. A gated oneshot creates the HA state directory, preventing initialization
on the disposable root. Borg quiesces HA and Tailscale while archiving `/persist`
so SQLite and node identity remain consistent. ZHA's coordinator backups are
stored with HA state and encrypted in the Borg repository.

The initial MR4U setup uses the CC2674P10 radio on TCP 7638 for ZHA
(`socket://SLZB_ADDRESS:7638`, ZNP, 115200 baud, no flow control). EFR32MG26 on
port 6638 remains unused for future Thread planning. The SMLIGHT integration uses
the MR4U management API and event stream on ports 80/81. Its credentials are
entered in HA and stored in permission-protected persistent state, encrypted in
Borg backups, never in Nix. Record
radio identity, firmware, socket mappings and access credentials in the private
operator inventory, not the public deployment contract.

## Immich files

| Path | Purpose |
|---|---|
| `/persist/immich/{thumbs,encoded-video,profile,backups}` | Generated media, profile images, built-in dumps; NVMe |
| `/persist/immich/{upload,library}` | Links to the two original-media directories on `/data` |
| `/data/immich/{upload,library}` | Bulk originals; NVMe initially, HDD migration eligible |
| `/persist/postgresql/17` | Live PostgreSQL; never raw-copied into Borg |
| `/persist/redis` | Redis queue state |
| `/persist/tailscale` | Node/SSH identity and Serve state |
| `/persist/secrets/{borg-passphrase,borg-ssh-key}` | Operator-enrolled root-only Borg credentials |
| `/persist/borg/{config,cache,known_hosts}` | Borg security/cache state and verified SSH trust |
| `/persist/backup/immich.dump` | Atomic logical database backup input |
| `/var/cache/immich` | Disposable downloaded models; may download again after replacement |

Mount guards check actual mounts, root-filesystem separation and exact marker
contents before stateful startup. Layout setup rejects unexpected directories/links;
it does not silently migrate existing data. All six `.immich` markers must survive.
Only `/data` may move to HDD. Proxmox ZFS size limits are quotas, not reservations.

CPU inference and Intel QSV are separate. The local ML patch adds an explicit
CPU-only environment policy after an OpenVINO segmentation fault. Regression
checks exercise actual installed provider selection. Remove the patch when upstream
provides a tested equivalent; never disable upstream tests to accommodate it.

## Add a service

1. Add `services/<name>/` with explicit upstream module/package configuration,
   state paths, fixed ownership, backup hooks and application tests.
2. Add a deployment that imports only required shared modules, supplies typed
   storage/secret/Tailscale options, and gates every stateful service on storage
   and readiness. Give the service its own identity and Borg repository.
3. Register configurations, catalog entries, contract and checks explicitly in
   the flake. Image variants are bootstrap, operational and recovery as required.
   Each image supplies `/etc/homelab-versions.json` for its manifest.
4. Verify that an unrelated service change leaves this image's derivation unchanged.
   Rehearse enrollment, replacement, backup failure and complete restoration.
