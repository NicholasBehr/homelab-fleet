# Verification matrix

Status as of 2026-11-11. Exact live GUIDs, identities, credentials and recovery
receipts remain in the protected operator inventory. Repository history contains
past release evidence; historical records never authorize a new mutation.

## Automated guarantees

| Area | Current coverage |
|---|---|
| Service completeness | Every `services/<name>` has a matching deployment, resource contract, service guide, catalog/configuration registration and service-specific Nix check set; flake assertions validate common contract and runtime wiring |
| Single-image lifecycle | Both services are inactive on fresh roots; tests cover failed activation, activation/deactivation, restart persistence, backup isolation and enabled-target bypasses |
| Runtime credentials | Metadata tests reject missing, empty, symlinked, non-regular, incorrectly owned or overly permissive files; image inputs contain paths and validation only |
| Storage guards | Disposable mount tests reject absent, root-backed and marker-mismatched volumes; Immich layout tests keep originals on `/data` and generated media on `/persist` |
| Backup recovery | Synthetic failure injection covers quiescing, Borg/dump failure, restart attempts and retained recovery intent; encrypted Borg/PostgreSQL fixtures exercise archive and logical restore |
| Application configuration | Immich checks exercise CPU-only ML selection, QSV wiring and backup runtime endpoints; Home Assistant checks cover loopback binding, ZHA/SMLIGHT, backup hooks and the full system closure |
| Image and release integrity | CI evaluates every configuration, selects changed derivations, builds images on separate runners, rejects runtime state in archives and fails closed through the stable required gate |
| Repository hygiene | Formatting, shell analysis, Python tests, secret-pattern scanning, service topology and public-doc address checks run before builds |

ARM macOS evaluates and lints Linux derivations; it does not build or execute Linux
systems. GitHub builds Linux checks and images without homelab credentials or
administrative access. These controls are not a Proxmox boot test or proof of a
particular live restore. Pattern scanning is heuristic, not proof that secrets are
absent.

## Operator-verified boundaries

| Area | Current evidence / boundary |
|---|---|
| Runtime credential adoption | All services use root-only `/persist/secrets` files and independently retrieved `borg-<service-slug>` Documents from the `Homelab` vault |
| Native unprivileged LXC | Boot, generated AppArmor/default ID mapping, nesting, private TUN permissions and Tailscale-only application access verified without host device-mode changes |
| Storage identity and replacement | Missing/swapped guards and managed root replacement verified; persistent volume identities and application state survived replacement |
| Immich placement and workload | Originals/generated media placement, representative synthetic uploads, search/face/OCR processing and Intel QSV transcode/playback verified |
| Backup and disaster recovery | Quiesced remote Borg backup, data verification, independent escrow retrieval, isolated PostgreSQL/media restore and fresh-volume/container recovery verified |
| Home Assistant and Zigbee | Single-image lifecycle, guarded state path, loopback HTTP, separate backup identity and ZHA network-backup procedure established; live coordinator details stay private |
| Secure Boot | Signed Proxmox boot, kernel lockdown, pools, service HTTPS and QSV verified after enablement |

An inactive replacement root does not clear Serve state stored with a restored
Tailscale identity. Keep Tailscale stopped during restoration; activation applies
the declared Serve policy before returning the service to operation. Never operate
duplicate Tailscale, Zigbee or application identities.

## Remaining workload-specific gates

- Validate capacity with the intended phone, 4K, 10-bit and mobile upload mix;
  synthetic media coverage is narrower.
- Rehearse Home Assistant restoration with replacement coordinator hardware before
  relying on that hardware-loss path.
- Treat any `/data` move to HDD as a separate identified-volume migration with a
  fresh consistent backup, explicit approval and restoration verification.
- Recheck backup freshness, independently restorable archives and identity
  exclusivity before every migration-bearing replacement.

Production readiness remains conditional on those workload-specific gates. Test
credentials, repositories and disposable volumes must never become production
resources, and retained recovery copies stay protected until their replacement is
independently verified.
