# Verification matrix

Status as of 2026-11-05. Historical commands/results remain in Git history; exact
live GUIDs, identities and recovery receipts are in the protected operator inventory,
not this public repository. Historical evidence never authorizes a new mutation.

| Check | Evidence / boundary |
|---|---|
| Linux builds, secret/mount guards, Borg/PG fixture restore | Passed on revised source; v0.1.0 images built and released from the checked main commit |
| Release verification | All seven v0.1.0 assets passed operator attestation/hash checks; manifests, versions and contracts matched reviewed source |
| Unprivileged native NixOS LXC boot | Passed with nesting=1; generated AppArmor/default ID mapping retained |
| TUN/render permissions and discovery listeners | Passed after declarative fixes; no host device mode changes |
| Missing/swapped mount identity guards | Passed on designated disposable volumes; no empty fallback state |
| Managed root replacement | Passed repeatedly; volume GUIDs, sentinels, account/assets and identities survived |
| Tailscale checked admin SSH/HTTPS, isolation | Passed; rehearsal identities only; physical-LAN scoped negative probes passed |
| SOPS enrollment and independent recovery | Passed; 1Password Document save/retrieval and decryption verified |
| Upload and generated-file placement | Passed: two synthetic originals on data; thumbnails/previews/encoded on persist |
| Actual QSV Immich job | Passed HEVC input to H.264 output, hardware decode/encode and playback |
| CPU inference fix | Actual Smart Search, face and OCR jobs processed both synthetic assets without worker crash |
| Encrypted off-guest backup and isolated restore | Passed media hashes, recovered age-key match, PG17 DB/extension restore and asset/user counts |
| Revised direct backup flow | Generated native job passed on a designated LXC: success, repository failure (exit2), dump failure (exit17), automatic service recovery and Borg data verification; local test repository, no remote endpoint |
| Complete fresh-volume/container disaster restore | Passed with independent 1Password retrieval, off-guest encrypted repository and fresh volumes; original hashes, two assets/one user/two search embeddings, identities, permissions and normal v0.1.0 startup matched; operator confirmed thumbnails/playback; new backup and API recovery passed |
| Remote Borg / retention | Passed on a dedicated test Storage Box subaccount: independently verified SSH host key, Borg1.4.4 on both ends, encrypted native-job backup/data check, synthetic retention deletion and isolated media/PG17 restore; live services recovered |
| Remote recovery escrow | Passed: 1Password save/download matched; retrieved credentials with fresh Borg client state opened the remote repository and recovered the exact DB dump; escrowed encrypted key matched the working repository key |
| Production identities/resources | Not enrolled or allocated; rehearsal ciphertext must be replaced |
| Secure Boot | Passed: enabled, signed Proxmox shim selected, kernel integrity lockdown active; pools healthy, Tailscale reachable, restored rehearsal services/HTTPS healthy. Postboot QSV encode passed as the application user with bundled Jellyfin FFmpeg; full Immich job/playback evidence above predates this reboot |
| Representative phone/4K/10-bit/mobile uploads | Conditional on intended workload; synthetic test success is narrower |
| Storage templates and later HDD migration | Not enabled/tested; separate validation and identified-volume migration required |

## CI guarantees and limits

ARM macOS formats, lints and evaluates Linux derivations; it does not build/run
Linux. GitHub tests real disposable mounts, encrypted Borg with PostgreSQL, secret
round-trips, hook failures and image layout. These are not a Proxmox boot test or
proof of production restoration. Pattern scanning is heuristic, not proof of no
secret leakage. CI has no homelab credentials or network access.

Nix derivation comparison selects affected images/checks. Missing old schema/base
falls back to all outputs. Current evaluation failures fail CI. Local actual-derivation probes passed: docs selected none, an Immich Serve-target
change selected operational/recovery images while leaving bootstrap/shared fixture
unchanged, and a shared base change selected all images plus the shared fixture.
The first refactor CI run built every output successfully. Cache handoff between
validation and image jobs was observed; eviction never changes correctness.

Evidence: [main checks](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41540226308)
and [v0.1.0 release](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41542334793)
passed at `f30f578959ea26b562125a89ffe86d519c9b29d9`. Full rehearsal receipts
remain private. The native-job test copied the evaluated job/sandbox/helpers into
runtime files on backup-disabled images; it supplied required Borg runtime
directories explicitly. Remote testing used the privately evaluated native job
with the test endpoint; no production timer was enabled. Production's identity,
repository, enabled job and timer still need enrollment and verification.
The recovery image does not clear saved Serve
state automatically; the operator reset it before restoring PostgreSQL.

Before production: enroll production
identities/resources and verify their scheduled backup
and recovery configuration. Test credentials/repositories must not become production.
Synthetic rehearsal does not establish capacity or representative-media coverage.
Host cleanup follows successful recovery checks
and exact provenance/attachment verification; retained recovery copies stay protected.
