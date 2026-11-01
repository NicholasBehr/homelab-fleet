# homelab-fleet

Disposable, unprivileged NixOS LXC images for Proxmox. Immich is the first service;
Intel Quick Sync transcoding and CPU machine learning are configured separately.
`/persist` stays on NVMe; `/data` holds bulk originals and can later move to HDD.
GitHub builds images; an operator verifies and pulls explicit releases. There is
no deployment script, runner, daemon, or CI route into the homelab.

**Status:** repository implementation under validation, not a production deployment.
Linux checks passed for code commit `8f0f49a` ([run](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41357621979)),
including all three templates and the TUN permission regression check.
Verified bootstrap and secret-free operational releases passed Proxmox device,
listener and retained-volume checks. Missing/wrong-volume guards and disposable
rootfs replacement passed. Synthetic H.264/HEVC QSV encode/decode passed using
Immich's FFmpeg/account with its service-hardening settings.
CT990–994 are stopped with test storage retained. Tailscale/age enrollment,
actual Immich jobs and application backup/restore remain unverified.
See the rehearsal runbook and validation boundaries.
Production backups are unconfigured until a Storage Box and secrets are enrolled.

## Read first

1. [Architecture and persistence contract](docs/architecture.md)
2. [Storage layout and later HDD migration](docs/storage.md)
3. [Observed host and proposed approval batches](docs/host-plan.md)
4. [Disposable host rehearsal](docs/rehearsal.md)
5. [First provisioning](docs/provisioning.md)
6. [Secrets enrollment](docs/secrets.md)
7. [Replacement](docs/deployment.md)
8. [Backups and restoration](docs/backup-restore.md)
9. [Recovery](docs/recovery.md)
10. [Validation boundaries](docs/validation.md)

`provision/containers.nix` is the authoritative proposed resource contract. IDs,
capacities and ownership assignments are proposals, not existing resources.
Run `nix eval --json .#deploymentContract` to inspect it. After every approved
replacement, update its current/next ID fields before another deployment.

On this ARM Mac: `nix develop path:.` supplies formatting, age, SOPS and shell tools.
`nix eval path:.#nixosConfigurations.immich.config.system.build.toplevel.drvPath`
checks evaluation without building Linux software. GitHub runs `scripts/check`
in `nix develop .#ci`; it explicitly builds both systems and template archives.

NixOS 26.05 is pinned. Its Immich 2.7.5 is marked insecure in the pinned source;
the Immich package and module therefore come from a separately pinned unstable
input. PostgreSQL 17 and the base system remain stable. `system.stateVersion`
remains 26.05 and is not an update switch. Review both pins and upstream Immich
migration notes before releasing. GitHub Actions are pinned by commit too.

No repository, release, push, or host mutation is authorized by the existence of
these files. Configure main-branch review protections before publishing releases.
