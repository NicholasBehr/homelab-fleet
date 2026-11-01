# First provisioning (manual; approval required)

All host-writing commands below are a proposed batch for review, not authorization.
Run commands interactively with `set -euo pipefail`; stop on any unexpected result.
Read deployment.md artifact verification first. Do not use `latest`.

## Artifact acquisition

On the Mac, select the reviewed full commit and variant after successful Actions:

```sh
REPO=NicholasBehr/homelab-fleet
COMMIT=REPLACE_WITH_REVIEWED_40_HEX_COMMIT
VARIANT=immich-bootstrap
TAG="$VARIANT-$COMMIT"
mkdir -p /tmp/homelab-release
cd /tmp/homelab-release
gh release download "$TAG" --repo "$REPO"
for asset in *.tar.xz *-manifest.json *-SHA256SUMS; do
  gh attestation verify "$asset" --repo "$REPO" --signer-workflow "$REPO/.github/workflows/release.yml"
done
shasum -a 256 -c "$VARIANT-SHA256SUMS"
jq . "$VARIANT-manifest.json"
```

Check commit, variant, contractVersion, versions and complete deployment contract
against the reviewed repository. Check attestation verification identifies the
expected main-branch release workflow and reviewed commit; do not accept merely
any workflow in the repository. GitHub OIDC/attestations authenticate the build
identity, assuming GitHub, maintainer controls, pinned actions and build inputs are
trusted. Checksums alone only detect corruption. Keep verified manifest locally.
The initial repository must first be published by a separately authorized user.

Proxmox pulls public assets over HTTPS (approved host file writes). Use the exact
asset name from the verified manifest, not a URL copied from untrusted output:

```sh
REPO=NicholasBehr/homelab-fleet
COMMIT=REPLACE_WITH_SAME_REVIEWED_40_HEX_COMMIT
VARIANT=immich-bootstrap
TAG="$VARIANT-$COMMIT"
ARCHIVE="$VARIANT-$COMMIT-x86_64-linux.tar.xz"
cd /var/lib/vz/template/cache
curl --fail --location --proto '=https' --tlsv1.2 -o "$ARCHIVE" "https://github.com/$REPO/releases/download/$TAG/$ARCHIVE"
sha256sum "$ARCHIVE"
```

Compare the exact digest to the Mac-verified checksum over the authenticated
Tailscale SSH session. Stop on mismatch. No gh installation is needed on Proxmox.
Retain commit, verified digest and manifest in the deployment record.

## Proposed resource allocation

Contract: `nix eval --json .#deploymentContract` on Mac. Recheck `pct list`, storage
space, bridge, default subordinate ID ranges and render PCI association first.
Check DHCP/reservation and outbound DNS/HTTPS availability. CT200 and CT201 must
both be free. Use the installed native `nixos` setup plugin: it writes the
networkd DHCP and DNS configuration that this image expects. `unmanaged` skips
that setup and is unsuitable for this network configuration. Both persistent volumes initially use NVMe local-zfs; no hddpool
change is needed:

```sh
CT=200
pct create "$CT" "local:vztmpl/$ARCHIVE" --ostype nixos --unprivileged 1   --hostname immich --cores 6 --memory 12288 --swap 0 --onboot 0   --rootfs local-zfs:32   --mp0 local-zfs:256,mp=/persist,backup=1   --mp1 local-zfs:512,mp=/data,backup=1   --net0 name=eth0,bridge=vmbr0,ip=dhcp,ip6=manual,firewall=1   --dev0 /dev/dri/renderD128,uid=0,gid=303,mode=0660   --dev1 /dev/net/tun,uid=0,gid=0,mode=0600
pct config "$CT"
pct mount "$CT"
ROOT="/var/lib/lxc/$CT/rootfs"
mountpoint "$ROOT"
mountpoint "$ROOT/persist"
mountpoint "$ROOT/data"
# NEW EMPTY VOLUMES ONLY. Verify mount sources against pct config before writing.
test ! -e "$ROOT/persist/.homelab-volume"
test ! -e "$ROOT/data/.homelab-volume"
chown 100000:100000 "$ROOT/persist" "$ROOT/data"
chmod 0711 "$ROOT/persist" "$ROOT/data"
printf '%s\n' homelab-immich-persist-v1 > "$ROOT/persist/.homelab-volume"
printf '%s\n' homelab-immich-media-v1 > "$ROOT/data/.homelab-volume"
chown 100000:100000 "$ROOT/persist/.homelab-volume" "$ROOT/data/.homelab-volume"
pct unmount "$CT"
pct start "$CT"
pct exec "$CT" -- systemctl status storage-contract tailscaled --no-pager
```

Do not recursively chown media. Proxmox managed-volume backup=1 is intentional;
vzdump capacity must cover media. Bind mounts would NOT automatically be included.
Never run pct destroy, pvesm free, or volume unlink as incidental cleanup.

Enroll through `pct enter 200`, following secrets.md; Tailscale enrollment command:

```sh
tailscale up --ssh --accept-routes=false --advertise-tags=tag:immich
```

Follow the interactive login URL in your authenticated browser; no auth key in
arguments or CI. Approve tag ownership policy first. Verify Tailscale SSH from Mac
before relying on it. Bootstrap publishes no application Serve endpoint.
Keep onboot=0 until replacement/recovery tests pass. See deployment.md to replace
bootstrap with the operational release while retaining both volumes.
