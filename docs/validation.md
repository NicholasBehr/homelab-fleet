# Verification matrix

Status as of 2026-11-10. Historical commands/results remain in Git history; exact
live GUIDs, identities and recovery receipts are in the protected operator inventory,
not this public repository. Historical evidence never authorizes a new mutation.

| Check | Evidence / boundary |
|---|---|
| Runtime credential transition (v0.4.0) | In progress: local metadata regression tests cover private modes, empty files, wrong ownership, unsafe directory permissions and non-regular files. Production replacement and independent fresh-volume restoration remain required; earlier SOPS evidence below applies only to historical releases |
| Linux builds, secret/mount guards, Borg/PG fixture restore | Passed for v0.2.1 at the checked main commit |
| Release verification | All seven v0.2.1 assets passed provenance, attestation and checksum verification; manifests, versions and contracts matched reviewed source |
| Unprivileged native NixOS LXC boot | Passed with nesting=1; generated AppArmor/default ID mapping retained |
| TUN/render permissions and discovery listeners | Passed after declarative fixes; no host device mode changes |
| Missing/swapped mount identity guards | Passed on designated disposable volumes; no empty fallback state |
| Managed root replacement | Passed repeatedly; volume GUIDs, sentinels, account/assets and identities survived |
| Tailscale checked admin SSH/HTTPS, isolation | Passed for the production tag and identity; no LAN service exposure. One transient simultaneous control/DERP outage affected both Linux nodes and recovered without configuration changes; monitor for recurrence |
| SOPS enrollment and independent recovery | Passed with production identities; 1Password Document save/retrieval and independent decryption verified |
| Upload and generated-file placement | Passed: two synthetic originals on data; thumbnails/previews/encoded on persist |
| Actual QSV Immich job | Passed HEVC input to H.264 output, hardware decode/encode and playback |
| CPU inference fix | Actual Smart Search, face and OCR jobs processed both synthetic assets without worker crash |
| Encrypted off-guest backup and isolated restore | Passed media hashes, recovered age-key match, PG17 DB/extension restore and asset/user counts |
| Revised direct backup flow | Generated native job passed on a designated LXC: success, repository failure (exit2), dump failure (exit17), automatic service recovery and Borg data verification; local test repository, no remote endpoint |
| Complete fresh-volume/container disaster restore | Passed with independent 1Password retrieval, off-guest encrypted repository and fresh volumes; original hashes, two assets/one user/two search embeddings, identities, permissions and normal v0.1.0 startup matched; operator confirmed thumbnails/playback; new backup and API recovery passed |
| Remote Borg / retention | Passed on a dedicated test Storage Box subaccount: independently verified SSH host key, Borg1.4.4 on both ends, encrypted native-job backup/data check, synthetic retention deletion and isolated media/PG17 restore; live services recovered |
| Remote recovery escrow | Passed: 1Password save/download matched; retrieved credentials with fresh Borg client state opened the remote repository and recovered the exact DB dump; escrowed encrypted key matched the working repository key |
| Production enrollment | Passed on v0.2.1: unprivileged operational LXC, declared production volumes, stable age/Tailscale identities, dedicated Storage Box repository and mode-restricted runtime secrets verified |
| Production backup and recovery | Native IPv4 Borg backup, `--verify-data`, independent escrow access and isolated media/PG restore passed. The separate full-volume rehearsal above covers container reconstruction. Daily 02:15 Europe/Zurich timer is active; application remains offline for the full backup |
| Production replacement and cleanup | v0.2.1 root replacement preserved exact production volume/identity GUIDs and service health. Rehearsal CTs, disposable datasets and obsolete image caches were removed after creation-record, GUID and sole-attachment checks; the prior production root remains stopped as rollback material |
| Secure Boot | Passed: enabled, signed Proxmox shim selected, kernel integrity lockdown active and pools healthy. Production services, HTTPS and bundled Jellyfin FFmpeg QSV passed afterward |
| Representative phone/4K/10-bit/mobile uploads | Conditional on intended workload; synthetic test success is narrower |
| Storage templates and later HDD migration | Not enabled/tested; separate validation and identified-volume migration required |

## CI guarantees and limits

ARM macOS formats, lints and evaluates Linux derivations; it does not build/run
Linux. GitHub tests real disposable mounts, encrypted Borg with PostgreSQL, secret
round-trips, hook failures and image layout in uncompressed tar archives. Release
jobs build the compressed operator artifacts. These are not a Proxmox boot test or
proof of production restoration. Pattern scanning is heuristic, not proof of no
secret leakage. CI has no homelab credentials or network access.

Nix derivation comparison selects affected images/checks. Missing old schema/base
falls back to all outputs. Current evaluation failures fail CI. Local actual-derivation probes passed: docs selected none, an Immich Serve-target
change selected operational/recovery images while leaving bootstrap/shared fixture
unchanged, and a shared base change selected all images plus the shared fixture.
The first refactor CI run built every output successfully. Cache handoff between
validation and image jobs was observed; eviction never changes correctness.

Evidence: [v0.2.1 main checks](https://github.com/NicholasBehr/homelab-fleet/actions/runs/42487039074)
and [v0.2.1 release](https://github.com/NicholasBehr/homelab-fleet/actions/runs/42487982978)
passed at `370df06b4e729ae1afa88dd53b27b0848fd88d28`. Full operator receipts
remain private. The native-job test copied the evaluated job/sandbox/helpers into
runtime files on backup-disabled images; it supplied required Borg runtime
directories explicitly. Remote testing used the privately evaluated native job
with a disposable test endpoint before production enrollment.
The recovery image does not clear saved Serve
state automatically; the operator reset it before restoring PostgreSQL.

Production is ready for imports, subject to the workload-specific capacity and
representative-media checks above. Test credentials/repositories must never become production.
Synthetic rehearsal does not establish capacity or representative-media coverage.
Retained production recovery copies stay protected.
