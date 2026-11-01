# Validation boundaries

Local checks on the ARM Mac can evaluate x86 Nix derivations, format Nix, lint
shell, exercise hook failure paths with mocked external commands and round-trip
SOPS with disposable keys. They cannot build/run the x86 image or prove LXC support.

GitHub Linux checks explicitly build bootstrap/operational systems and tarballs,
run hook failure tests, perform real PostgreSQL dump/restore through encrypted local
Borg, and exercise real mount absence/wrong-marker guards in a disposable mount
namespace. The namespace persistence test changes a disposable directory root;
it does NOT emulate Proxmox rootfs replacement. Source leak checks are heuristic,
not a claim that arbitrary secrets are detectable. CI receives no deployment secrets.

Before calling the deployment validated, record these host results with approval:
- Bootstrap boot without secrets; correct DHCP, console and default confinement.
- Age enrollment, operational decryption after actual rootfs replacement.
- Missing mp0/mp1 and intentionally wrong disposable-volume markers prevent DB,
  Redis, Immich and tailscaled startup. No new DB/media files on disposable root.
- Managed volume transfer/detach semantics using approved test CT990/991; compare
  checksums/ownership before and after; no persistent cleanup in ordinary replacement.
- Successful backup, failed prepare and failed remote Borg operation restore services;
  failed backup prevents deployment. Fresh-volume DB/extension/media restore rehearsal.
- Tailscale authorized SSH/HTTPS succeeds, unauthorized policy tests fail; LAN TCP22,
  TCP111, TCP2283 and host TCP8006 unreachable from another physical-LAN device.
- Upload a test photo/video, generate thumbnails and transcode. Verify realpath and
  filesystem placement: originals on /data, all generated files on /persist.
  Preserve all six .immich markers across replacement; exercise storage templates
  if enabled, and record the native symlink layout compatibility.
- Real representative H.264/HEVC media transcodes via QSV. Inside container run:

```sh
vainfo --display drm --device /dev/dri/renderD128
runuser -u immich -- ffmpeg -hide_banner -v verbose -init_hw_device qsv=hw:/dev/dri/renderD128 \
  -filter_hw_device hw -hwaccel qsv -hwaccel_output_format qsv \
  -i /data/immich/OPERATOR_SELECTED_REPRESENTATIVE_VIDEO -c:v h264_qsv \
  -an -t 15 -f null -
```

Use approved representative media; confirm logs identify hardware decode AND encode,
not just a visible node. Exercise actual Immich transcode job, inspect its FFmpeg
logs/output, play resulting video, compare duration/frame count. Test available
codecs separately; unsupported codecs are not a reason to weaken confinement.
ML remains CPU and does not validate GPU media acceleration. These hardware tests
have not been run by repository implementation.

Template layout checks also require /sbin/init and reject runtime files under
/persist, /data and /run/secrets. These complement source secret-pattern checks;
no automatic scanner can establish absence of every possible credential format.

## Recorded local result, 2026-11-01 (storage contract v2)

Passed on the ARM Mac: all-system flake evaluation (including backup-enabled
configuration), Nix formatting, ShellCheck, ten layout/hook tests, source secret
pattern scan, and SOPS round-trip using both disposable container/recovery keys.
The layout tests verify writes and original-file renames through the links,
retained integrity markers, and rejection of existing directories/wrong links.
The separate-filesystem placement test is in tests/storage-linux.sh, pending CI.
No Linux image build, actual Immich boot, Proxmox test or host mutation performed.

## Interactive verification order

1. Review and explicitly authorize the initial commit/push to the existing public
   NicholasBehr/homelab-fleet repository; run Checks. No release is needed for CI.
2. Inspect Linux results and fix failures. Separately authorize publication of the
   exact bootstrap release, then verify its attestation/digest on the Mac.
3. Present an exact, small disposable-host batch with current free CT IDs and volume
   limits. Approve before downloading/writing anything on Proxmox, then verify
   secret-free boot, mounts, render/TUN devices, confinement and volume transfers.
4. Enroll test identities together through the authenticated console. Publish an
   explicitly approved encrypted operational image; exercise actual Immich upload,
   thumbnail/encoded-video placement and GPU transcoding, then replacement.
5. Test consistent local Borg failure/recovery and fresh-volume restoration using
   disposable assets. Configure real remote backup only after Storage Box enrollment.
6. Approve real service allocations after the disposable rehearsal. Any cleanup
   or later /data migration is a separate batch; /persist always stays on NVMe.

## CI archive-build diagnosis, 2026-11-01

The first Linux run passed ten unit/layout/hook tests and reached all system
builds in about three minutes, then spent over 24 minutes in three concurrent
upstream tarball derivations without progress output before being canceled for
investigation. This does not establish successful template builds. The upstream
builder copies each system closure before compressing it, so simultaneous archives
also duplicate temporary disk work.

CI now separates lint, evaluation, runtime tests, system builds and each template
into named steps. Archives build sequentially with one Nix build job; the exported
image packages use pixz level 1 with two compression workers. They retain the same
.tar.xz deployment format, at the cost of potentially larger downloads. Each phase
has a 15-minute limit, the whole job a 60-minute limit, and build logs are enabled.
Release builds use the same exported packages/settings as checks. `scripts/check`
retains an all-phases entry point; individual phases accept the documented stage
arguments visible in the workflow. The corrected Linux run subsequently passed; see the recorded result below.


## Recorded Linux result, 2026-11-01

[Run 41348167681](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41348167681)
passed for code commit 3ce2eb001e096e01ac0bf0ecf24af989a720fc4d in 15 minutes
2 seconds. Ten unit/layout/hook tests, secret round-trip, real encrypted local
Borg/PostgreSQL restore, mount failure/placement checks, all four system
configurations, and all three exported image builds/layout checks passed.

Archive build plus layout-check times: bootstrap 2m19s, operational 4m39s,
recovery 5m14s. Reported archive sizes: 667 MiB, approximately 1.4 GiB and 1.4 GiB.
These times include copying system closures and reading each archive for layout
verification; they are not isolated compressor benchmarks. No Proxmox boot,
GPU/Tailscale integration or real Immich data restoration has yet been verified.
No release was published and no Proxmox mutation was performed. Documentation-only
updates recording these results do not require repeating the image builds.


## First actual host result, 2026-11-01

Approved batch A created CT990 from the verified bootstrap release and left it
stopped with rootfs and both persistent volumes retained. Mount identities and
device ownership checks passed; storage-contract succeeded. Actual boot integration
FAILED: AppArmor denied move mounts and user namespace creation; networkd and
journald/tmpfiles failed. /run/current-system and graphics driver links were absent.
DNS, functional Tailscale and GPU acceleration are not validated. This does not
supersede the successful Linux CI result; it demonstrates its hardware/LXC limits.
See docs/rehearsal.md for the evidence, retained volumes, and unapproved R1 retry.


## Approved R1 host result, 2026-11-01

Enabling the supported nesting feature on unprivileged CT990 resolved the observed
systemd failures. Zero failed units, DHCP, DNS, HTTPS200, the storage gate, normal
runtime links and Intel iHD VA-API capabilities were verified. Generated AppArmor
confinement and standard ID maps remain. Tailscale CLI reports NeedsLogin; enrollment
was not performed. CT990 is stopped with every volume retained.

TUN became0666 via guest static-node tmpfiles rules, despite configured0600;
systemd-resolved also has wildcard discovery listeners, blocked by the active
firewall. Both should be corrected declaratively in a future image and retested.
Actual video decode/encode, app-account access, physical-LAN reachability,
Tailscale SSH/Serve, replacement and real Immich restoration remain unverified.
