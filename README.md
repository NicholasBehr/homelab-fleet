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

**Status:** All services use the single-image lifecycle and independently escrowed
runtime Borg credentials. Immich has verified QSV, remote backup, fresh-volume
restoration and managed root replacement. Home Assistant has the same inactive-root,
storage, credential and backup boundaries; its Zigbee-specific recovery procedure
is documented separately. See [validation](docs/validation.md) for the exact
evidence and remaining workload-specific checks.

- [Architecture, layout and adding services](docs/architecture.md)
- [Service onboarding contract](docs/adding-a-service.md)
- [Immich backup and restoration](docs/immich.md)
- [Home Assistant and Zigbee](docs/home-assistant.md)
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
