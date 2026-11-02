# homelab-fleet

Unprivileged NixOS LXC images for Proxmox, with Immich as the first service.
GitHub builds and attests images; operators pull explicit verified releases.
CI has no homelab access. Root filesystems are replaced, while declared data and
identities survive on external volumes. `/persist` stays on NVMe; `/data` is bulk
originals suitable for later HDD migration.

**Status:** rehearsal application, storage, root replacement, Tailscale, SOPS,
QSV video and CPU inference passed. Production is not enrolled; remote backups
and complete fresh-volume recovery remain outstanding. The revised direct Borg
flow and refactored images require regression testing. See [validation](docs/validation.md).
SOPS ciphertext currently belongs to disposable rehearsal identities, not production.

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
