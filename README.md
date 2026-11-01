# homelab-fleet

Disposable, unprivileged NixOS LXC images for Proxmox. Immich is the first service;
Intel Quick Sync transcoding and CPU machine learning are configured separately.
`/persist` stays on NVMe; `/data` holds bulk originals and can later move to HDD.
GitHub builds images; an operator verifies and pulls explicit releases. There is
no deployment script, runner, daemon, or CI route into the homelab.

**Status:** repository implementation under validation, not a working deployment.
The storage split is contract v2; local layout/hook tests pass.
Linux checks passed for code commit `3ce2eb0` ([run](https://github.com/NicholasBehr/homelab-fleet/actions/runs/41348167681)).
All three x86 templates built; actual Proxmox boot and hardware validation remain pending.
No containers or host changes have been made.
Production backups are unconfigured until a Storage Box and secrets are enrolled.

## Read first

1. [Architecture and persistence contract](docs/architecture.md)
2. [Storage layout and later HDD migration](docs/storage.md)
3. [Observed host and proposed approval batches](docs/host-plan.md)
4. [First provisioning](docs/provisioning.md)
5. [Secrets enrollment](docs/secrets.md)
6. [Replacement](docs/deployment.md)
7. [Backups and restoration](docs/backup-restore.md)
8. [Recovery](docs/recovery.md)
9. [Validation boundaries](docs/validation.md)

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
