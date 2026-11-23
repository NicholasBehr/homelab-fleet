# Jellyfin

Jellyfin runs in its own unprivileged NixOS LXC. Its HTTP listener is configured
for `127.0.0.1:8096`; Tailscale Serve provides the private HTTPS endpoint. The
physical-LAN firewall remains closed. Intel QSV uses the standard render-device
sharing configuration and the NixOS Intel media userspace. The planned i5-14500
provides UHD Graphics 770: use QSV for H.264/HEVC encoding and H.264, HEVC,
VP9 and AV1 decoding. Do not assume AV1 hardware encoding on this desktop iGPU.
Keep integrated graphics enabled in firmware and verify the host's render-device
mapping before provisioning.

| Path | Purpose |
|---|---|
| `/persist/jellyfin` | Configuration, database, users, watch state, metadata, thumbnails and logs |
| `/persist/jellyfin/cache` | Jellyfin cache |
| `/persist/jellyfin/transcodes` | Transcode temporary files; select this in Jellyfin's transcoding settings |
| `/data/media/movies` | Imported movie originals |
| `/data/media/tv` | Imported TV originals |
| `/data/staging/movies` | Incomplete or not-yet-published movie transfers |
| `/data/staging/tv` | Incomplete or not-yet-published TV transfers |
| `/persist/secrets/rclone.conf` | Root-only SFTP endpoint and authentication configuration |
| `/persist/secrets/rclone_known_hosts` | Root-only, independently verified SFTP server host key |

The proposed `/data` contract is 10 TiB on HDD and is **not backed up**. It contains
only regenerable media originals and transfer staging. Borg archives `/persist`
only, including Jellyfin's database/configuration and the protected rclone
enrollment files. Treat the remote as the source for rebuilding media after a
local `/data` loss.

## SFTP import

The importer uses rclone's SFTP subsystem; it does not require remote shell
commands. The protected rclone config must define a remote named `source`, rooted
so that `source:movies` and `source:tv` are the remote directories to pull. For
example, its non-secret settings include:

```ini
[source]
type = sftp
host = <remote-sftp-host>
user = <remote-sftp-user>
port = 22
known_hosts_file = /persist/secrets/rclone_known_hosts
shell_type = none
disable_hashcheck = true
skip_links = true
```

Use a remote account restricted to read-only access to the media directories.
Configure authentication in that runtime file using the SFTP account's supported
method. The file may contain credentials and must remain root:root mode0600 under
`/persist/secrets` mode0700. Do not put credential values in Git, Nix expressions,
commands, logs or chat. Pin the SFTP host key using a key verified out of band;
do not use trust-on-first-use for unattended imports. For password authentication,
use rclone's interactive config editor to write its obscured `pass` value;
obfuscation is reversible, so the file remains a secret.

At activation the importer runs once, then repeats five minutes after each run
finishes. It uses `rclone copy` into the matching staging tree and compares against
the media tree to avoid fetching already-published files. It never uses `sync`,
deletes local media when a remote file disappears, or removes files remotely.
After both category copies succeed, rclone lists the current remote files and
promotion validates the staged size and modification time against that listing.
Files no longer present remotely are not promoted. Staged files are published
without overwriting existing library paths; a name collision fails the job and
preserves both copies for operator review. Interrupted or failed copies remain in
staging for retry; stale staging files are not deleted automatically.

Since shell-based checksums are disabled for SFTP-only access, rclone's
compare-destination check uses size and modification time. Keep remote movie/TV
paths immutable with stable, unique names and accurate modification times. The
remote should expose files only after upload completion (for example, upload under
a temporary name and rename to the final name). A five-minute poll gives ample
margin for the stated multi-day retention, but cannot compensate for a remote
outage or a file being deleted during a transfer. Import failures are visible in
the `rclone-import.service` status and journal; each later timer run retries.

## Release, enrollment and acceptance

Build and publish one `jellyfin` image through the normal PR, required-check and
exact-main release process. The contract's CT IDs, `hddpool` storage name, volume
sizes and render-device path are proposals, not live inventory or authorization.
Verify them against the private operator inventory before provisioning. Verify
the exact `/persist` and `/data` volume creation records, attachments and markers
before any storage mutation. Never attach a production or retained recovery
volume to a rehearsal.

Enroll Jellyfin's dedicated Tailscale identity and Borg repository/credentials as
the core operational block. Store and independently verify the
`borg-jellyfin` recovery Document in the `Homelab` vault. The rclone settings are
an independent import block, included only in encrypted `/persist` backups; images
contain their file paths, not their contents. Missing SFTP enrollment keeps the
import service and timer inactive without blocking Jellyfin, Tailscale or Borg.

On a fresh root, verify both marked volumes and the core root-only runtime files
before `homelab-activate`. Enroll rclone before expecting its import timer to run.
Then verify:

1. Tailscale Serve works over HTTPS, Jellyfin health responds locally, and the
   listener is bound only to `127.0.0.1`; no Jellyfin port is reachable on the
   physical LAN.
2. The dashboard's transcode path is `/persist/jellyfin/transcodes`. Play
   representative media and verify QSV hardware decoding and H.264/HEVC encoding
   inside the container, not just the presence of the render device.
3. Use disposable synthetic remote files to check a successful poll, identical
   second poll, failed/partial transfer retry, both media categories, no
   propagation of a remote deletion, and collision preservation.
4. Take a consistent Borg backup and independently restore Jellyfin state into
   fresh, correctly marked test storage. Confirm `/data` is absent from the Borg
   archive and that media can be fetched again from the remote. CI also exercises
   a synthetic local Borg archive and SQLite state restore without media.

Keep the replacement inactive during restoration. Start only manually approved
restore helpers, preserve fresh volume markers, and activate after verifying
credential readiness and Tailscale identity exclusivity.
