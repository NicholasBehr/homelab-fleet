# Verification matrix

Status as of 2026-11-02. Historical commands/results remain in Git history; exact
live GUIDs, identities and recovery receipts are in the protected operator inventory,
not this public repository. Historical evidence never authorizes a new mutation.

| Check | Evidence / boundary |
|---|---|
| Linux builds, secret/mount guards, Borg/PG fixture restore | Passed before refactor; required again for revised source |
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
| Revised direct backup flow | Local hook tests plus Linux fixture checks required; actual job success/failure and service recovery outstanding |
| Complete fresh-volume/container disaster restore | Outstanding; scratch DB/media recovery does not cover it |
| Remote Borg / retention / escrow | Unconfigured; production enrollment and actual backup/restore outstanding |
| Production identities/resources | Not enrolled or allocated; rehearsal ciphertext must be replaced |
| Secure Boot | Operator temporarily disabled; enable after boot/signature inspection, then reboot/ZFS/network/QSV checks |
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
First refactor CI run must build every output. Cache speedups
must be measured; eviction never changes correctness.

Before production: pass refactor CI, rehearse direct backup failure recovery and
complete fresh-volume restoration, enable/verify Secure Boot, enroll production
identity and actual remote backup. Host cleanup follows successful recovery checks
and exact provenance/attachment verification; retained recovery copies stay protected.
