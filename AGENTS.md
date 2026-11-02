# Durable rules
- Unprivileged NixOS LXC only; Immich first; standard Intel render-device sharing.
- Replace disposable images; no routine production nixos-rebuild or deploy-rs.
- Persist data and identity only on declared volumes. /persist stays on NVMe; /data contains only bulk originals suitable for HDD migration. Keep DBs, thumbnails, previews and encoded video on /persist.
- GitHub builds/releases only; no homelab credentials or administrative access.
- Operators pull explicit verified releases. MVP provisioning/replacement is manual.
- Tailscale-only access; preserve confinement and Secure Boot (temporarily disabled by operator decision, 2026-11-01).
- Read-only host discovery is allowed. Mutations confined to designated test containers and verified disposable test volumes are permitted without further approval. Storage authorization requires a creation record identifying the exact volume; container IDs, names and current attachment alone are insufficient. Before storage mutations, verify provenance and attachments. Never include production volumes, retained recovery data or sole backups. If verification is incomplete or inconsistent, ask for approval. Changes to the underlying Debian/Proxmox host, shared infrastructure or production resources require explicit approval of exact commands.
- Never put plaintext secrets in Git, images, the Nix store, or logs.
- Require consistent backups before migration-bearing updates.
- Keep imports explicit and modules simple; test replacement and restoration.
- Never delete persistent storage outside verified disposable test volumes, or assume software rollback reverses migrations.

# Repository rules
- `modules/` contains reusable NixOS modules with typed options; never import a service deployment or hardcode its ports, paths or service names there.
- `services/<name>/` owns application configuration, package overrides, patches, backup hooks and application tests. `deployments/` composes explicit imports and operator resource contracts. `lib/` contains small construction helpers; `flake.nix` registers outputs explicitly.
- Keep upstream NixOS modules where practical. Document local patches with their rationale, regression check and removal condition. Avoid automatic directory imports and speculative frameworks.
- Backups may keep the application offline for the entire Borg operation. Prefer direct reads of quiesced state over duplicate media staging. Dump databases logically, exclude their live files, attempt every required restart on failure, and preserve recovery intent when restart fails.
- Work on short-lived branches and submit a PR with required CI checks before merging to main. Release only an exact main commit with successful checks; publication and deployment are distinct operations.
- `VERSION` is repository SemVer, initially 0.1.0. Never modify an existing release/tag. Keep upstream application versions and storage-contract versions separate. Compatibility covers manifests, output names, persistent paths/markers, ownership, secret requirements and recovery procedures. Document migrations explicitly; version numbers do not promise database rollback safety.
- Build image archives on separate runners (at most three concurrent), not concurrently on one runner. Preserve the stable `Required checks` gate; failed/cancelled dependencies must fail it and an empty image selection must skip builds safely.
- CI compares evaluated image/check derivations with the base commit; unavailable base means build all. Current evaluation failures fail CI. Cache misses rebuild normally. Keep docs and Git revision metadata out of runtime image inputs unless required.
- Validate formatting, shell, application hook failure recovery, storage guards, secret handling and affected Linux systems/images. ARM macOS evaluates/lints; GitHub builds Linux. Rehearse full restoration before production.
- Keep docs current and compact. `docs/validation.md` is the verification matrix; history is in Git. Live GUID inventories, node/account identities, credentials and recovery receipts stay outside this public repository. Never treat historical test records as live storage authorization.
