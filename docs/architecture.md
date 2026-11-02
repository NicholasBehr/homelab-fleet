# Architecture

## Code boundaries

`modules/` implements shared base hardening, native Proxmox LXC integration,
mount-identity guards, SOPS readiness, Tailscale, optional Intel userspace and Borg.
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
Only SOPS ciphertext may be included; plaintext decryption happens at runtime.

Unprivileged default UID mapping, generated AppArmor confinement and test-validated
`nesting=1` remain. No privileged LXC, unconfined profile, DKMS, VF or kernel changes.
Render sharing uses `/dev/dri/renderD128` with fixed guest render GID303; TUN is0600.
Native `ostype=nixos` and `manageNetwork=false` let Proxmox supply networking.
Tailscale provides checked SSH and HTTPS Serve; ordinary sshd is disabled. App and
ML bind loopback. The firewall exposes no application ports to the physical LAN.

## Immich files

| Path | Purpose |
|---|---|
| `/persist/immich/{thumbs,encoded-video,profile,backups}` | Generated media, profile images, built-in dumps; NVMe |
| `/persist/immich/{upload,library}` | Links to the two original-media directories on `/data` |
| `/data/immich/{upload,library}` | Bulk originals; NVMe initially, HDD migration eligible |
| `/persist/postgresql/17` | Live PostgreSQL; never raw-copied into Borg |
| `/persist/redis` | Redis queue state |
| `/persist/tailscale` | Node/SSH identity and Serve state |
| `/persist/secrets/age-key.txt` | Root-only age identity |
| `/run/secrets/{borg-passphrase,borg-ssh-key}` | Runtime SOPS plaintext; root-only |
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
