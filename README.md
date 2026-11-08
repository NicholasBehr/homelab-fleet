# homelab-fleet

Unprivileged NixOS LXC images for Proxmox, with Immich as the first service.
GitHub builds and attests images; operators pull explicit verified releases.
CI has no homelab access. Root filesystems are replaced, while declared data and
identities survive on external volumes. `/persist` stays on NVMe; `/data` is bulk
originals suitable for later HDD migration.

**Status:** Immich production is running from the verified v0.2.1 operational
image. Tailscale-only access, SOPS enrollment, QSV, direct remote Borg backup,
independent recovery escrow, full fresh-volume restoration and managed root
replacement are verified. The scheduled backup runs daily at 02:15
Europe/Zurich. See [validation](docs/validation.md) for boundaries and remaining
workload-specific checks.

- [Architecture, layout and adding services](docs/architecture.md)
- [Enrollment, releases and replacement](docs/operations.md)
- [Backup and disaster recovery](docs/recovery.md)
- [Verification matrix](docs/validation.md)
- [Release policy and current changes](docs/release-notes.md)

`deployments/immich-contract.nix` proposes resources; it does not inventory live
containers or authorize allocations. Inspect with `nix eval --json .#deploymentContracts.immich`.
Keep exact creation records and live volume GUIDs in a protected operator inventory.

On ARM macOS, `nix develop path:.` provides local tools. Run `scripts/check lint`
and `nix flake check --no-build`; Linux builds run on GitHub. Open a PR from a short-lived
branch. Checks always evaluate configurations and run runtime fixtures, then build
only changed derivations. Releases use repository SemVer from `VERSION` and include
catalog images, manifests, checksums and GitHub provenance. No automatic deployment.
