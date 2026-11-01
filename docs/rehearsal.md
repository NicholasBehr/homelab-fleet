# Disposable Proxmox rehearsal

Status: **corrected bootstrap and secret-free operational releases 8f0f49a passed device/listener/storage checks. Synthetic H.264 and HEVC QSV encode/decode passed under the Immich account and hardening settings. CT990–994 are stopped; all test storage retained. Application enrollment and actual Immich/restore rehearsals remain.**
The underlying Debian/Proxmox host and production mutations require exact-command
approval. Under AGENTS.md, designated test containers and verified disposable test
volumes may now be managed autonomously. Historical batch approvals below describe
the policy in effect when those batches ran. Verify creation provenance and all
attachments before each storage mutation; stop on unexpected output.

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

## Retry R1: supported nesting feature on CT990 only

**Approved and executed on 2026-11-01.** The default-profile boot failed at ordinary
NixOS/systemd namespace and mount operations. The next isolated test is the
supported Proxmox nesting flag. It keeps CT990 unprivileged and under Proxmox's
generated AppArmor confinement, but expands permitted namespace/mount operations
and exposes additional host procfs/sysfs views. It is a security tradeoff, not a
pure performance flag. No privileged mode, unconfined profile, extra devices,
keyctl, FUSE, host driver change or host-wide policy change is proposed.

The installed /usr/share/perl5/PVE/LXC.pm explicitly documents this behavior and
adds lxc.apparmor.allow_nesting plus allow userns for this feature. See also the
[Proxmox container manual](https://pve.proxmox.com/pve-docs/pct.1.html).
The isolated test resolved core boot. Production resource declarations remain
unchanged until nesting is explicitly approved for the service contract.

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

## R1 result, 2026-11-01

- Core boot succeeded with nesting=1: zero failed units, active storage-contract,
  tailscaled, networkd, journald, tmpfiles and container firewall. The normal
  /run/current-system and /run/opengl-driver links exist.
- Native setup obtained IPv4 DHCP; outbound DNS and a clean HEAD request to
  https://github.com returned HTTP 200.
- Tailscale CLI connected and reported NeedsLogin, as expected without enrollment.
  No age key or Tailscale login was generated or enrolled.
- Persistent mounts are the same two local-zfs subvolumes, with markers retained.
- Render node remains root:render (0:303), mode0660. Intel iHD driver 26.1.6 loaded
  with VA-API 1.23 and advertised H.264/HEVC decode/encode capabilities. This query
  ran as container root; actual media transcoding and Immich-account access are
  NOT validated by it.
- Proxmox generated AppArmor confinement remained active, with its supported
  allow_nesting/userns additions. UID/GID maps remain 0:100000:65536.
- Runtime TUN permissions drifted from configured 0600 to 0666. The cause is the
  guest's /etc/tmpfiles.d/static-nodes-permissions.conf rule. This needs a
  declarative image correction before final deployment; no manual chmod was used.
- systemd-resolved opened mDNS/LLMNR listeners (UDP5353/5355 and TCP5355) on wildcard
  addresses. Effective IPv4/IPv6 INPUT rules accept loopback, established traffic
  and tailscale0, then drop other unsolicited traffic; no ordinary SSH or application
  listener was present. Discovery listeners should still be disabled in the image.
  This inspection does not replace an independent physical-LAN reachability test.
- CT990 shut down successfully and is stopped. All three volumes, the archive,
  onboot=0 and the approved nesting feature are retained. CT991 is still absent.

Off-host non-secret evidence is in /private/tmp/homelab-rehearsal-r1 on the Mac.
The two runtime-policy deviations above were observed, not silently repaired on
Proxmox. R1 establishes the boot requirement but is not final deployment readiness.

## Later batches (historical scope of batch A and R1)

After inspecting A's results, prepare exact commands with actual allocated volume
IDs for CT991 creation, sentinel writes, stopped-container mp0/mp1 transfer,
checksum/ownership checks, and wrong/missing-volume boot tests. Never start both
containers with the same writable state. After those pass, separately approve
age-key generation/enrollment, representative GPU decode/encode, actual Immich
layout, application-consistent backup and restoration. No production media is
needed for the rehearsal. The subsequently approved AGENTS.md test-resource rule
permits autonomous iteration and cleanup only with verified disposable provenance.


## Post-R1 batch B result, 2026-11-01

Executed under the approved AGENTS.md test-resource policy. Before mutations,
compared batch A's creation record with exact current volume IDs and every LXC
attachment; only CT990 existed. Recorded ZFS GUIDs off-host before transfers.
[Resource provenance](test-resources.json) records creation and rename history;
it must be checked against live attachments before future storage mutations.

- Added synthetic sentinels to both disposable volumes, UID/GID 1100, mode0600,
  and recorded SHA256 checksums. No production data or credentials were involved.
- Created designated CT991 with a new 16 GiB root on local-zfs from the same
  authenticated bootstrap archive, native nixos setup, unprivileged mapping,
  generated AppArmor, nesting=1, two cores/4 GiB, onboot=0 and the same two devices.
- Booted CT991 without persistent mounts: storage-contract failed with
  `Required mount absent: /persist`; tailscaled remained inactive and no new
  Tailscale state appeared under the disposable root's /persist.
- With both containers stopped, ran `pct move-volume 990 mp0 --target-vmid 991
  --target-volume mp0` and the corresponding mp1 transfer. Proxmox renamed datasets
  to subvol-991-disk-1/2; their GUIDs remained unchanged. CT990 retains its old root.
- Swapped only the two test mount destinations while stopped. Wrong markers
  failed storage-contract and blocked tailscaled. Restored correct destinations.
- Booted the replacement with correct volumes: both sentinel checksums,
  UID/GID1100 and mode0600 survived. Zero failed units; tailscaled reported NeedsLogin.
  This proves bootstrap state transfer across distinct roots, not enrolled
  Tailscale identity continuity, age decryption or database migration safety.
- Attempted QSV using bootstrap's diagnostic FFmpeg 8.1.3; initialization failed.
  Build configuration shows both libvpl and libmfx disabled. This binary cannot
  validate QSV; the operational Immich wrapper uses a separate Jellyfin FFmpeg.
- Synthetic VA-API H.264 encode AND hardware decode passed as numeric UID/GID1100
  with supplementary render group303: 60 frames, 320x240, two seconds. Output was
  written only to CT991's /tmp/rehearsal-qsv. This is application-equivalent Unix
  device access, not an actual Immich job or representative codec workload.
- Both containers ended stopped. All four datasets remain. No underlying host
  packages, drivers, pool settings, firewall or networking configuration changed.

Non-secret command output and results: /private/tmp/homelab-rehearsal-b on the Mac.
The test-volume root files contain synthetic sentinels only, alongside bootstrap
runtime state; neither volume is a production volume or a sole backup.

Code commit d6aa0707cf842401a6e415872aace0617e4b4909 adds an early tmpfiles TUN
mode0600 rule and disables resolved LLMNR/mDNS. Local lint, ten unit tests and
all-system evaluation passed. GitHub Linux checks are running at
[run 41354418773](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41354418773).
No new release or in-place image repair has been performed; the runtime fixes
still require a fresh verified image boot.


### Independent IPv4 LAN probes

The Mac used source 192.168.1.49 with direct en0 routes, independently of Tailscale.
Proxmox 192.168.1.55 had an en0 ARP entry; TCP22/111/443/8006 were unreachable and
ICMP did not reply. CT991 obtained 192.168.1.60; it answered ICMP over that same
physical LAN, while TCP22/111/2283/5355 were unreachable. TCP5355 was a confirmed
listening systemd-resolved socket during the probe, so this tests firewall blocking
rather than merely absence of a listener. CT991 was then stopped again.

Evidence: /private/tmp/homelab-rehearsal-b/host-lan.json and guest-lan.json.
These are tested IPv4 TCP endpoints only; no claim is made for IPv6, UDP or every
possible LAN source. Tailscale authorized/unauthorized policy testing is separate.


## Post-R1 batch C result, 2026-11-01

Approved release from d6aa0707cf842401a6e415872aace0617e4b4909 was published after
[checks 41354418773](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41354418773)
and [release 41355554753](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41355554753)
passed. Exact [bootstrap release](https://github.com/NicholasBehr/homelab-fleet/releases/tag/immich-bootstrap-d6aa0707cf842401a6e415872aace0617e4b4909):
699,240,968-byte archive, SHA256
`98d3cde88dda350fc78b19d80fe36fa8e56237bb844cdae0c5e43a0868e1371d`.

All three assets passed attestation verification restricted to the exact
source/signer commit, release workflow, main source ref and GitHub-hosted runners.
Manifest versions/contract matched reviewed local expectations; checksums and tag
matched. Off-host receipt: /private/tmp/homelab-bootstrap-d6aa070/verification-receipt.json.

Created designated unprivileged CT992 from that verified image, with nesting and
the same test limits/devices as CT991. Only its new 16 GiB root was allocated.
Before transfer, verified both source GUIDs and references across all cluster LXC
and QEMU configurations. Both containers were stopped. Transferred mp0/mp1 from
CT991 using supported move-volume; dataset GUIDs survived another ownership rename.
All five allocated datasets are retained; current IDs are in test-resources.json.

- The first probe ran before boot settled because a multi-unit `is-active` call
  succeeds when any named unit is active. Corrected readiness to check each unit
  individually and wait for tmpfiles completion before judging the image.
- Settled boot had zero failed units and active storage/tailscaled/network/resolved.
- LLMNR=false and MulticastDNS=false were present; wildcard discovery sockets were
  gone on IPv4 and IPv6. Only loopback DNS, DHCP and Tailscale sockets remained.
- Render stayed 0:303 mode0660, but TUN still became 0:0 mode0666. Therefore this
  released image does NOT pass the requested TUN permission policy.
- Debug tmpfiles replay showed both z rules execute, first0600 then vendor0666.
  The previous assumption that an earlier z rule overrides the vendor entry was
  incorrect. Tailscale itself did not cause the mode change.
- In a runtime experiment confined to CT992, copied the vendor file to /run,
  changed only its TUN mode and applied those rules only to /dev/net/tun. Mode0600
  held across tailscaled restart; CLI reported NeedsLogin. Both sentinels passed
  checksums. This is a diagnostic experiment, not a boot-validated image fix.
- CT990, CT991 and CT992 ended stopped. No production identity or data was enrolled,
  and no underlying host configuration, driver or source-device permission changed.

The revised Nix module replaces only the vendor file's TUN mode, preserving other
entries, and fails the build if the pinned vendor text changes unexpectedly.
A Linux tmpfiles regression check applies the generated rule set to a disposable
fixture and requires mode0600. Revised image publication and fresh boot remain
pending; local lint, ten unit tests and all-system evaluation passed.

Command evidence: /private/tmp/homelab-rehearsal-c on the Mac. The /run experiment
is ephemeral and did not modify the released Nix store or install an in-place fix.


## Batch D: corrected bootstrap verification

The operator gave standing image build/publication/test approval for this session
while there is no production data. This does not change the durable approval
requirements for the underlying Debian/Proxmox host or production resources.

[CI 41357621979](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41357621979)
passed for 8f0f49aebcb7fddf78d123fc13b623d80a7ce78f, including the new real tmpfiles
permission regression check, all four system configurations and all three images.
[Bootstrap release run 41357828208](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41357828208)
passed and published the exact
[bootstrap release](https://github.com/NicholasBehr/homelab-fleet/releases/tag/immich-bootstrap-8f0f49aebcb7fddf78d123fc13b623d80a7ce78f).
Its 699,140,544-byte archive has SHA256
`abaa56d3d183b246a1a53a7846518ac1236abff986ebf0bd0aa1d7543b5c5297`.

Independently verified all three assets with the same exact-commit/workflow/ref
attestation policy as batch C, tag, checksums and reviewed manifest expectations.
Receipt: /private/tmp/homelab-bootstrap-8f0f49a/verification-receipt.json.

Created designated CT993 with a new 16 GiB root and the same unprivileged/nesting
and device settings. Rechecked creation GUIDs and all cluster LXC/QEMU attachments
before transferring the two test volumes from stopped CT992. Also checked that
no production media, enrolled age identity, Immich/database state or staged backups
had entered the test volumes. Transfer retained GUIDs and sentinels.

Fresh boot passed:
- TUN was 0:0 mode0600 before any diagnostic replay; render was 0:303 mode0660.
- Reapplying the actual tmpfiles rules and restarting tailscaled retained0600.
- Zero failed units; storage, Tailscale, networkd and resolved active.
- No ordinary SSH, application or LLMNR/mDNS listeners on either address family.
- Both sentinel hashes, owner1100:1100 and mode0600 retained on distinct ZFS mounts.
- DHCP, DNS/HTTPS200 and Intel iHD VA-API initialization passed.
- Tailscale stayed NeedsLogin. No age key or application data was enrolled.

CT993 was stopped, all storage retained. Evidence: /private/tmp/homelab-rehearsal-d.
The vendor-rule replacement is now boot-validated; this supersedes batch C's
remaining TUN defect for the new release, without retroactively validating d6aa070.


### Batch D: operational image and hardened QSV verification, 2026-11-01–02

[Operational release run 41358067859](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41358067859)
passed and published the same source commit's secret-free
[operational image](https://github.com/NicholasBehr/homelab-fleet/releases/tag/immich-8f0f49aebcb7fddf78d123fc13b623d80a7ce78f).
Archive: 1,455,205,248 bytes, SHA256
`dfeda3fe69a51ebb77750aa709bec4458b8937e35095af7ad8a6ae7f51488e36`.
Independently verified all three asset attestations, checksums, exact tag and
reviewed manifest; encryptedSecretsIncluded=false. Local receipt:
/private/tmp/homelab-immich-8f0f49a/verification-receipt.json.

Created designated unprivileged CT994 with a fresh 16 GiB root and the same
nesting/device/test resource settings. Verified GUIDs, data classification and
all cluster LXC/QEMU references before transferring the two disposable volumes
from stopped CT993. Their GUIDs stayed unchanged. No volumes were deleted.

The operational image behaved as intended without credentials: operational-ready
failed with `Enroll container age identity first`; PostgreSQL, Redis, Immich and
machine learning remained inactive, with no database PG_VERSION on either the
persistent path or disposable root. TUN was0600, render0:303 mode0660; no SSH,
application, database or discovery listener appeared. Tailscale remained NeedsLogin.

Ran synthetic H.264 and HEVC QSV encode AND decode using the exact Jellyfin FFmpeg
8.1.3-1 binary referenced by the Immich package, as the actual immich UID/GID1100.
A transient test unit applied the evaluated service's CapabilityBoundingSet,
NoNewPrivileges, PrivateUsers/Tmp/Devices/Mounts, DeviceAllow, ProtectClock,
ProtectControlGroups/Home/Hostname/KernelLogs/KernelModules/KernelTunables,
RestrictAddressFamilies/Namespaces/Realtime/SUIDSGID, SupplementaryGroups and UMask.
No service-hardening flag was relaxed. The fixture excluded application startup,
readiness dependencies, credentials and application state/runtime directories;
its only command was the synthetic media test under /run/rehearsal-qsv.

Both codecs encoded and hardware-decoded all 60 frames at 320x240/30fps, with
zero decode errors. oneVPL2.16 initialized the Intel iHD26.1.6 driver. Forced QSV
decoders and hardware frame output prevented CPU fallback; ffprobe and decoder
progress checks confirmed frame counts. Unit exited0/SUCCESS. Its PrivateUsers
namespace displayed supplementary groups as nogroup; render access still worked.
This establishes the tested hardware path and sandbox compatibility, not an
actual Immich transcode job, representative 4K/10-bit input or every codec.

The first harness attempt failed before GPU execution because non-login PATH
lacked cat. Corrected the harness to use absolute paths and reran without changing
the image. Both sentinel hashes, ownership and modes passed afterward. Application
and database stayed stopped throughout. No age key or SOPS credentials were created.

Final check: CT990–994 stopped, all seven datasets retained, only CT994 references
the two test-state volumes. Host render/TUN source-device permissions stayed
unchanged. Underlying host packages, kernel, drivers, networking, firewall and
storage configuration were not changed. Test provenance is in test-resources.json;
full non-secret evidence is in /private/tmp/homelab-rehearsal-d on the Mac.

Next: interactive Tailscale and age/recovery enrollment, then actual Immich upload,
thumbnails/transcode placement, identity-preserving replacement and consistent
backup/fresh-volume restoration. Remote Borg needs a real Storage Box and escrow.
No production deployment or production nesting approval is implied by these tests.


## Interactive rehearsal enrollment, 2026-11-02

Operator selected disposable rehearsal identities, not eventual production
identities. CT994's exact creation GUIDs and all cluster references were checked
before startup/key generation. Created its age key under /persist/secrets with
mode0600, displaying only the public recipient. Independently generated a protected
recovery identity and unique rehearsal Borg credentials outside the repository;
only the public recipients and SOPS ciphertext are committed. Recovery decryption
matched both credentials entirely in memory. 1Password Document import/retrieval
verification is in progress; preserve enrollment fixtures until recovery checks pass.

Operator supplied the existing tailnet policy. Prepared a separate tag:immich-test
addition preserving hypervisor/app01 rules, with infra-admin HTTPS/checked-root-SSH
and denial tests between the rehearsal node and existing services. Operator saved
it after built-in tests passed, completed guest login and machine approval.
No live tailnet policy or user-specific policy copy is committed to this repository.

Node immich-rehearsal.dorper-shade.ts.net / 100.102.210.15 reports Running with the
correct test tag. Operator verified Tailscale SSH returns UID0 and hostname immich.
Serve points to loopback2283, but the current image remains application-gated until
a verified ciphertext-bearing replacement. This is test enrollment only; the
underlying Debian/Proxmox host SSH/network/policy configuration was not modified.

Current local files are protected under /private/tmp/homelab-enrollment-rehearsal;
private contents have never been printed. Exact public recipients and enrollment
classification are recorded in test-resources.json. SOPS material in this source
is rehearsal-only and must be replaced before any production enrollment.
