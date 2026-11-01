# Disposable Proxmox rehearsal

Status: **batch A approved and executed on 2026-11-01; first boot failed integration checks; CT990 is stopped with all volumes retained. Retry R1 awaits approval.**
Every host mutation requires approval under AGENTS.md. These are reviewed manual
commands, not a deployment script. Run each block interactively, inspect results,
and stop on unexpected output. Do not execute later batches implicitly.

## Verified prerequisites

- Public secret-free release: `immich-bootstrap-ed093486cd8036fd3770038165a389e156bd8e74`.
- Its archive, manifest and checksums were downloaded to the Mac and verified using
  GitHub attestations restricted to the release workflow, main ref and exact
  source/signer commit. Local receipt: `/private/tmp/homelab-bootstrap-ed09348/verification-receipt.json`.
- Archive SHA256: `c8bcb0826bf301d113e74f5b0422bc73b6455b8a614ba9c7a2e67ae0067b6287`.
- Read-only host refresh: Proxmox 9.2.24; no containers; CT990 and CT991 free;
  local-zfs has ~3.51 TiB available; vmbr0 is up on 192.168.1.55/24.
- Render node /dev/dri/renderD128 still resolves to Intel PCI 0000:00:02.0.
- Standard UID/GID mapping is root:100000:65536. No custom maps are proposed.
- Host DNS is 192.168.1.1; the native setup plugin copies it into the new guest.
- Native Proxmox `nixos` setup writes networkd configuration; `unmanaged` does not.
  The image uses networkd and expects native setup. No nesting is proposed.

## Batch A: verify download, create CT990, boot/check, leave stopped

Approval covers the following effects:

- Download one 699,137,000-byte archive to local template storage; verify it
  against the independently authenticated Mac digest before using it.
- Allocate CT990: unprivileged, two CPU cores, 4096 MiB RAM, zero swap, onboot=0,
  16 GiB disposable root plus 1 GiB /persist and 1 GiB /data, all on local-zfs.
  These are temporary test quotas, separate from the eventual service allocation.
- DHCP veth on vmbr0 with firewall=1; render device container root:303 mode0660;
  TUN container root:root mode0600. Host source-device permissions stay unchanged.
- Initialize only the two new empty volume roots and identity markers, then boot.
  Boot may create runtime state and an unenrolled Tailscale identity on /persist.
- Query storage, networking, listening sockets, Tailscale readiness and VA-API
  capability, then shut down CT990. Force-stop is allowed for this secret-free
  disposable test if graceful shutdown times out. Retain every allocated volume.

No host packages, drivers, firmware, storage configuration, firewall rules,
Tailscale policy or credentials are changed. The HDD pool is not used. No age-key
creation or Tailscale enrollment is part of this batch. No deletion is included.

### A1. Host preflight and verified download

Run through `ssh root@pve.dorper-shade.ts.net` in one host shell. Set strict failure
handling for the mutation blocks; a failure means stop and inspect, not continue.

```sh
set -euo pipefail
CT=990
COMMIT=ed093486cd8036fd3770038165a389e156bd8e74
TAG="immich-bootstrap-$COMMIT"
ARCHIVE="$TAG-x86_64-linux.tar.xz"
TEMPLATE="/var/lib/vz/template/cache/$ARCHIVE"
DIGEST=c8bcb0826bf301d113e74f5b0422bc73b6455b8a614ba9c7a2e67ae0067b6287

test ! -e /etc/pve/lxc/990.conf
test ! -e /etc/pve/lxc/991.conf
test ! -e "$TEMPLATE"
test ! -e "$TEMPLATE.partial"
test "$(readlink -f /sys/class/drm/renderD128/device)" = /sys/devices/pci0000:00/0000:00:02.0
pct list
pvesm status
curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --output "$TEMPLATE.partial" \
  "https://github.com/NicholasBehr/homelab-fleet/releases/download/$TAG/$ARCHIVE"
printf '%s  %s\n' "$DIGEST" "$TEMPLATE.partial" | sha256sum --check --strict -
mv -- "$TEMPLATE.partial" "$TEMPLATE"
```

The fixed digest is from the Mac's authenticated provenance verification, not
from an unauthenticated checksum fetched alongside the archive. HTTPS and the
Tailscale SSH session protect the transfer; the digest binds it to verified bytes.
If a partial/template already exists, inspect and verify it before proposing a
separate retry batch. Do not overwrite it silently.

### A2. Allocate CT990, mount and initialize its NEW empty volumes

```sh
pct create "$CT" "local:vztmpl/$ARCHIVE" \
  --arch amd64 --ostype nixos --unprivileged 1 \
  --hostname immich --cores 2 --memory 4096 --swap 0 --onboot 0 \
  --rootfs local-zfs:16 \
  --mp0 local-zfs:1,mp=/persist,backup=1 \
  --mp1 local-zfs:1,mp=/data,backup=1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp,ip6=manual,firewall=1 \
  --dev0 /dev/dri/renderD128,uid=0,gid=303,mode=0660 \
  --dev1 /dev/net/tun,uid=0,gid=0,mode=0600
pct config "$CT"
pct mount "$CT"
ROOT="/var/lib/lxc/$CT/rootfs"
mountpoint "$ROOT"
mountpoint "$ROOT/persist"
mountpoint "$ROOT/data"
findmnt --target "$ROOT/persist" --output SOURCE,TARGET,FSTYPE
findmnt --target "$ROOT/data" --output SOURCE,TARGET,FSTYPE
```

Pause and compare mount sources with the actual automatically allocated volume
IDs in pct config. Record those IDs off-host on the Mac; do not guess disk names.
The root, persist and data must be three distinct new local-zfs subvolumes.

```sh
test -z "$(find "$ROOT/persist" -mindepth 1 -maxdepth 1 -print -quit)"
test -z "$(find "$ROOT/data" -mindepth 1 -maxdepth 1 -print -quit)"
chown 100000:100000 "$ROOT/persist" "$ROOT/data"
chmod 0711 "$ROOT/persist" "$ROOT/data"
printf '%s\n' homelab-immich-persist-v1 > "$ROOT/persist/.homelab-volume"
printf '%s\n' homelab-immich-media-v1 > "$ROOT/data/.homelab-volume"
chown 100000:100000 "$ROOT/persist/.homelab-volume" "$ROOT/data/.homelab-volume"
chmod 0644 "$ROOT/persist/.homelab-volume" "$ROOT/data/.homelab-volume"
pct unmount "$CT"
```

The native setup plugin may populate files such as networking, DNS and unused SSH
host keys on the disposable root. Ordinary sshd remains disabled by the image;
Tailscale owns the service's eventual network identity. These unused keys need
no persistence. The logical hostname remains immich; CT990 identifies this disposable fixture.

### A3. Start and inspect

```sh
pct start "$CT"
pct status "$CT"
pct exec "$CT" -- /run/current-system/sw/bin/bash -lc \
  'systemctl --no-pager status storage-contract tailscaled systemd-networkd'
pct exec "$CT" -- /run/current-system/sw/bin/bash -lc \
  'systemctl --failed --no-pager; ip -brief address; findmnt -T /persist; findmnt -T /data'
pct exec "$CT" -- /run/current-system/sw/bin/bash -lc \
  'stat -c "%u:%g %a %n" /dev/dri/renderD128 /dev/net/tun; ss -lntup'
pct exec "$CT" -- /run/current-system/sw/bin/bash -lc \
  'tailscale status --json | jq -r .BackendState'
pct exec "$CT" -- /run/current-system/sw/bin/bash -lc \
  'curl --fail --connect-timeout 10 --max-time 20 --head https://github.com'
pct exec "$CT" -- /run/current-system/sw/bin/bash -lc \
  'vainfo --display drm --device /dev/dri/renderD128'
```

Wait for boot/network readiness before judging transient startup results. Use the
absolute bash entry point because host PATH is not the guest's NixOS login PATH.
Expected: correct separate mounts, active storage gate/tailscaled/networkd, DHCP,
DNS/HTTPS outbound, render 0:303 mode660, TUN 0:0 mode600, and Intel media capability.
Tailscale should be unenrolled (usually NeedsLogin); tailscale-policy may retry
until enrollment. There should be no ordinary SSH or application LAN listener.
VA-API visibility/capabilities do not prove actual decode/encode or Immich access;
those remain separate tests with explicit fixtures and application accounts.

If diagnostics fail, collect only relevant service logs (no credentials):

```sh
pct exec "$CT" -- /run/current-system/sw/bin/bash -lc \
  'journalctl -b -u storage-contract -u tailscaled -u systemd-networkd --no-pager -n 120'
```

### A4. Leave the fixture stopped, retaining all storage

```sh
pct shutdown "$CT" --timeout 30 --forceStop 1
pct status "$CT"
pct config "$CT"
```

If the guest never boots or shutdown cannot run, the explicitly approved fallback
for this disposable CT990 only is `pct stop 990`. If still mounted on the host,
`pct unmount 990` is also allowed as recovery. Leave the archive, rootfs, persistent
volumes and configuration intact; no cleanup/deletion command is authorized.

## Batch A result, 2026-11-01

- Verified download SHA256 matched the independently authenticated release.
- Created unprivileged CT990 with native nixos setup, default confinement, no nesting.
- Allocated and retained: rootfs local-zfs:subvol-990-disk-0 (16 GiB),
  /persist local-zfs:subvol-990-disk-1 (1 GiB),
  /data local-zfs:subvol-990-disk-2 (1 GiB). All reservation/refreservation
  properties are none; limits are refquota. CT991 was not created.
- Confirmed distinct ZFS mounts, marker initialization, and storage-contract success.
- Render ownership in guest is 0:303 mode0660; TUN is 0:0 mode0600.
- Native Proxmox setup generated the expected eth0.network with IPv4 DHCP.
- Boot FAILED: 21 failed systemd units, including networkd (243/CREDENTIALS),
  journald, tmpfiles and register-nix-paths. eth0 remained down; DNS/HTTPS failed.
- tailscaled process started but the local CLI could not connect; Tailscale is NOT
  validated. No enrollment, age-key generation or application startup occurred.
- /run/current-system and /run/opengl-driver were absent. VA-API initialization
  failed to locate runtime drivers; this does NOT establish a host Intel-driver
  problem or prove hardware acceleration. No transcoding test has passed.
- Kernel AppArmor audit entries for lxc-990 show denied move mounts at /nix/store,
  /run and /run/credentials, plus denied userns_create for systemd-managed units.
  Journald itself failed, so guest journal queries had no entries.
- Read-only diagnostics used the immutable system profile/store binaries when
  /run/current-system/sw/bin/bash was unavailable; no guest image edits were made.
- Approved shutdown completed; pct status is stopped. No storage was deleted,
  no driver/firewall/security setting changed, and no additional features enabled.

Off-host records are in /private/tmp/homelab-rehearsal-a on the Mac. Host kernel
logs and the installed PVE::LXC implementation provide direct evidence: nesting
adds the supported allow_nesting configuration and user-namespace permission.
The successful CI image builds did not prove these host integration requirements.

## Proposed retry R1: supported nesting feature on CT990 only

**Not approved and not executed.** The default-profile boot failed at ordinary
NixOS/systemd namespace and mount operations. The next isolated test is the
supported Proxmox nesting flag. It keeps CT990 unprivileged and under Proxmox's
generated AppArmor confinement, but expands permitted namespace/mount operations
and exposes additional host procfs/sysfs views. It is a security tradeoff, not a
pure performance flag. No privileged mode, unconfined profile, extra devices,
keyctl, FUSE, host driver change or host-wide policy change is proposed.

The installed /usr/share/perl5/PVE/LXC.pm explicitly documents this behavior and
adds lxc.apparmor.allow_nesting plus allow userns for this feature. See also the
[Proxmox container manual](https://pve.proxmox.com/pve-docs/pct.1.html).
Production resource declarations remain unchanged until this isolated test passes
and the feature is approved for the service contract.

Proposed approved effects: change only CT990's features, boot that same fixture,
repeat the read-only checks from A3, then stop it and retain all storage. No new
image, container or volume is needed.

```sh
set -euo pipefail
pct status 990  # must be stopped
pct config 990 # original config has no features line
pct set 990 --features nesting=1
pct config 990
pct start 990
```

Repeat A3's service, mounts, device ownership, socket, Tailscale readiness,
DNS/HTTPS and VA-API queries. Save relevant non-secret evidence on the Mac. Do not
enroll Tailscale or generate secrets. Stop at unexpected results and collect
read-only diagnostics; no further configuration changes are implicit.

```sh
pct shutdown 990 --timeout 30 --forceStop 1
pct status 990
pct config 990
```

Approved recovery for R1 would also cover `pct stop 990` if shutdown fails, and
removing the newly added features option while stopped to restore the original
feature settings. There was no original features line:

```sh
pct set 990 --delete features
pct config 990
```

Keep stopped with all three volumes and the verified archive retained. Do not
remove the feature while running or delete any volume. If nesting is unacceptable,
leave CT990 stopped and investigate a separately reviewed image adaptation; do
not broadly disable service sandboxing or host confinement to make it boot.

## Later batches (not covered by batch A approval)

After inspecting A's results, prepare exact commands with actual allocated volume
IDs for CT991 creation, sentinel writes, stopped-container mp0/mp1 transfer,
checksum/ownership checks, and wrong/missing-volume boot tests. Never start both
containers with the same writable state. After those pass, separately approve
age-key generation/enrollment, representative GPU decode/encode, actual Immich
layout, application-consistent backup and restoration. No production media is
needed for the rehearsal, and destructive cleanup needs its own approval.
