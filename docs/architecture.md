# Architecture

## Code boundaries

`modules/` implements shared base hardening, native Proxmox LXC integration,
mount-identity guards, runtime credential readiness, Tailscale, optional Intel userspace and Borg.
Modules declare options and never import service deployments. Each
`services/<name>/` directory owns native application settings, backup hooks and
service-specific tests. Each matching `deployments/<name>.nix` explicitly composes
shared modules and supplies storage, secret and endpoint settings; its adjacent
contract records proposed resources and fixed ownership. `lib/mk-container.nix`
constructs systems; the flake explicitly registers configurations, images,
contracts and prefixed service checks.

NixOS 26.05 is pinned in `flake.lock`. Immich's module/package use a separate
pinned unstable input because the stable package was marked insecure. Paperless-ngx
likewise uses its own pinned unstable module/package so application updates do not
advance either the fleet base or Immich. PostgreSQL 17 remains stable.
`system.stateVersion` stays 26.05; it is not an upgrade switch. Review every pin,
migration note and extension version before updates.

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
Zigbee2MQTT owns the Zigbee network and connects to the SLZB-MR4U over wired LAN
TCP. A loopback-only Mosquitto broker carries discovery, state and commands
between Zigbee2MQTT and Home Assistant. The SMLIGHT integration separately
provides coordinator monitoring and management. This deployment has no USB,
render device, Thread, OTBR or `/data`.

| Path | Purpose |
|---|---|
| `/persist/home-assistant` | SQLite database, `.storage`, automations and dashboards |
| `/persist/home-assistant/backups` | Home Assistant backup artifacts |
| `/persist/zigbee2mqtt` | Device database, coordinator backup, groups and runtime state |
| `/persist/mosquitto` | Retained loopback MQTT broker state |
| `/persist/tailscale` | Tailnet identity and Serve state |
| `/persist/secrets/{borg-passphrase,borg-ssh-key,zigbee2mqtt.env}` | Operator-enrolled root-only credentials and coordinator endpoint setting |
| `/persist/borg/{config,cache,known_hosts}` | Borg configuration, disposable cache and authenticated SSH trust |
| `/persist/borg/repository` | Private runtime repository URI |

The single `/persist` volume is guarded by its exact marker before any workload
starts. A gated oneshot creates the state directories, preventing initialization
on the disposable root. Borg quiesces Home Assistant, Zigbee2MQTT, Mosquitto and
Tailscale while archiving `/persist`, so SQLite, MQTT and Zigbee identity remain
consistent. Zigbee2MQTT generates its network identity on first startup and
stores it only in its persistent state directory.

The MR4U setup uses the CC2674P10 radio on TCP 7638 for Zigbee2MQTT
(`tcp://SLZB_ADDRESS:7638`, zstack, 115200 baud, no flow control). EFR32MG26 on
port 6638 remains unused for future Thread planning. The SMLIGHT integration uses
the MR4U management API and event stream on ports 80/81. Its credentials are
entered in HA and stored in permission-protected persistent state, encrypted in
Borg backups, never in Nix. Record
radio identity, firmware, socket mappings and access credentials in the private
operator inventory, not the public deployment contract.

## Jellyfin media

Jellyfin runs as a separate unprivileged service. Its network configuration binds
HTTP only to loopback; a dedicated Tailscale identity publishes HTTPS Serve.
Intel QSV uses the shared `/dev/dri/renderD128` render device and the common
`render` group. The proposed i5-14500 UHD Graphics 770 provides H.264/HEVC
encoding and AV1 decoding; verify actual acceleration on representative media.
The SFTP importer runs rclone without remote shell commands and only promotes
successful copies into the media library.

| Path | Purpose |
|---|---|
| `/persist/jellyfin` | Jellyfin configuration, database, users, watch state, metadata, thumbnails and logs |
| `/persist/jellyfin/cache` | Jellyfin cache |
| `/persist/jellyfin/transcodes` | Transcode temporary files |
| `/data/media/movies` | Bulk movie originals |
| `/data/media/tv` | Bulk television originals |
| `/data/staging/movies` | Movie transfer staging |
| `/data/staging/tv` | Television transfer staging |
| `/persist/secrets/rclone.conf` | Root-only SFTP endpoint/authentication |
| `/persist/secrets/rclone_known_hosts` | Verified SFTP host key |

The Jellyfin Borg archive covers `/persist` only. `/data` is a proposed 10 TiB HDD
volume containing regenerable originals and is deliberately excluded from backup.
The importer polls every five minutes, uses copy-only behavior, and never applies
remote deletions. See [Jellyfin](jellyfin.md) for SFTP enrollment, import
assumptions, acceptance and restoration.

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

## Nextcloud files

Nextcloud uses the native NixOS module, PostgreSQL 17 and Redis in a separate
unprivileged LXC. Tailscale Serve terminates private HTTPS; Nginx listens only on
loopback. There is no public ingress. The complete application data directory is
`/data/nextcloud`, including previews, versions and trash: this is the explicit
exception to the fleet's bulk-only `/data` policy. Configuration and database stay
on `/persist`; temporary uploads/buffers use `/data/nextcloud-tmp`.

The service has one normal home per user and native quotas. No external storage,
per-user mounts or impermanence. Directory creation is gated, initialization is
explicit without bootstrap passwords, and activation refuses absent application
state. See [Nextcloud](nextcloud.md) for the resource proposal, runtime endpoint
schema, account creation, quiesced backups and restoration procedure.

## Paperless-ngx files

Paperless-ngx 3.5.0 runs natively with PostgreSQL 17 and Redis. It accepts PDFs,
performs German and English OCR, and binds only to loopback behind Tailscale Serve.
Tika, Gotenberg, Office/email conversion, AI integrations and automatic update
checks are disabled. The deployment deliberately uses one guarded NVMe volume;
there is no `/data` split or render device.

| Path | Purpose |
|---|---|
| `/persist/paperless/data` | Tantivy index, classifier data, logs and application secret key |
| `/persist/paperless/media` | Original PDFs, generated PDF/A archives and thumbnails |
| `/persist/paperless/consume` | Pending PDF consumption |
| `/persist/postgresql/17` | Live PostgreSQL; excluded from Borg in favor of a logical dump |
| `/persist/redis` | Disposable task broker state |
| `/persist/backup/paperless.dump` | Atomic logical PostgreSQL backup input |
| `/persist/secrets/paperless.env` | Private tailnet HTTPS origin used for host/CORS/CSRF validation |

Upstream directory initialization and automatic multi-user startup are suppressed.
The manual initializer creates the schema and first administrator before writing a
persistent application marker; the disposable root's separate activation record is
still required to start normal operation. See [Paperless-ngx](paperless-ngx.md).

## Add a service

Follow the normative [service onboarding contract](adding-a-service.md). It defines
the required names, repository shape, deployment schema, lifecycle, versions JSON,
backup/recovery behavior, tests, flake registration, Tailscale policy and operator
acceptance gates. Registrations remain explicit and service modules remain simple;
there is no generator or automatic import layer.
