# homelab-fleet

Unprivileged NixOS LXC images for Proxmox, including Immich and Home Assistant.
GitHub builds and attests images; operators pull explicit verified releases.
CI has no homelab access. Root filesystems are replaced, while declared data and
identities survive on external volumes. `/persist` stays on NVMe; `/data` is bulk
originals suitable for later HDD migration. Home Assistant uses a single `/persist`
volume and a LAN connected SMLIGHT Zigbee coordinator.

One image per service supports enrollment, restoration and operation. New roots
keep applications, Tailscale and backup timers inactive until explicit systemd
activation; see [lifecycle](docs/lifecycle.md).

**Status:** Immich production is running from the verified v0.2.1 operational
image. Tailscale-only access, legacy SOPS enrollment, QSV, direct remote Borg backup,
independent recovery escrow, full fresh-volume restoration and managed root
replacement are verified. The scheduled backup runs daily at 02:15
Europe/Zurich. See [validation](docs/validation.md) for boundaries and remaining
workload-specific checks.

The v0.4.0 single-image/runtime-credential transition is under validation; it has
not replaced the running production deployment.

- [Architecture, layout and adding services](docs/architecture.md)
- [Enrollment, releases and replacement](docs/operations.md)
- [Backup and disaster recovery](docs/recovery.md)
- [Verification matrix](docs/validation.md)
- [Release policy and current changes](docs/release-notes.md)

`deployments/immich-contract.nix` proposes resources; it does not inventory live
containers or authorize allocations. Inspect with `nix eval --json .#deploymentContracts.immich`.
Keep exact creation records and live volume GUIDs in a protected operator inventory.
Home Assistant's proposed resources are in
`deployments/home-assistant-contract.nix`; its IDs are not live allocation records.

On ARM macOS, `nix develop path:.` provides local tools. Run `scripts/check lint`
and `nix flake check --no-build`; Linux builds run on GitHub. Open a PR from a short-lived
branch. Checks always evaluate configurations and run runtime fixtures, then build
only changed derivations. Releases use repository SemVer from `VERSION` and include
catalog images, manifests, checksums and GitHub provenance. No automatic deployment.
