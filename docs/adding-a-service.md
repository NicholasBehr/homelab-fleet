# Adding a service

This is the normative contract for every published service. Existing services are
executable examples, but neither service is a template to copy without reviewing
its application-specific storage and recovery behavior. Registrations stay
explicit; do not add automatic directory imports or a service generator.

## Names and repository shape

Choose one lowercase kebab-case slug, for example `example-service`, and use it for
the service directory, deployment, contract, image output, catalog key, manifest
service, Tailscale tag and Borg recovery Document suffix:

```text
services/example-service/default.nix
services/example-service/backup-prepare
services/example-service/backup-cleanup
services/example-service/tests/checks.nix
services/example-service/tests/test_backup_hooks.py
deployments/example-service.nix
deployments/example-service-contract.nix
docs/example-service.md
```

Nix-local variables use ordinary camelCase where a kebab-case identifier would be
awkward. External names and JSON keys use the exact service slug. Application
options may follow upstream naming when required.

## Deployment contract

The adjacent contract is a proposed resource contract, never a live inventory or
storage authorization. It must define:

- `service`, equal to the slug; `architecture = "x86_64-linux"`; and `hostname`;
- proposed initial/replacement IDs, CPU, memory, swap, bridge and network settings;
- `root` and a guarded `persist` volume whose path is `/persist`;
- an `application` attribute set containing service-specific state paths, ports and
  fixed application ownership;
- `uidOffset`, `gidOffset`, `tunDevice` and a positive `contractVersion`;
- optional volumes or devices only when the service actually requires them.

Every persistent volume needs a stable slot, path and unique marker. `/persist`
stays on NVMe. Declare `/data` only for bulk originals that may later move to HDD;
databases, indexes, thumbnails, previews and encoded output remain on `/persist`.
Advance `contractVersion` whenever the exported contract schema or a compatibility
value changes. Repository SemVer and upstream application versions are independent.

A minimal single-volume contract starts like this; replace every proposal and add
only genuinely required application/device fields:

```nix
{
  service = "example-service";
  architecture = "x86_64-linux";
  hostname = "example-service";
  initialId = 220;
  replacementId = 221;
  cores = 2;
  memoryMiB = 2048;
  swapMiB = 0;
  bridge = "vmbr0";
  network = "name=eth0,bridge=vmbr0,ip=dhcp,ip6=manual,firewall=1";
  root = { storage = "local-zfs"; sizeGiB = 32; };
  persist = {
    slot = "mp0";
    storage = "local-zfs";
    sizeGiB = 32;
    path = "/persist";
    marker = "homelab-example-service-persist-v1";
  };
  application = {
    state = "/persist/example-service";
    port = 1234;
    uid = 1110;
    gid = 1110;
  };
  uidOffset = 100000;
  gidOffset = 100000;
  tunDevice = "/dev/net/tun";
  contractVersion = 1;
}
```

## Service and deployment

The service module owns upstream application configuration, fixed users/groups,
state layout, backup hooks and application tests. It must:

- bind application listeners to loopback and leave the physical-LAN firewall closed;
- put all identity and state on declared volumes, never the disposable root;
- gate every stateful service and directory initializer on `storage-contract` and
  `operational-ready`;
- suppress upstream targets or timers that could bypass explicit activation;
- write `/etc/homelab-versions.json` with an exact slug key for the application
  version and `contractVersion`; add dependency versions needed for restoration;
- quiesce the application for the entire Borg operation and make cleanup attempt
  every required restart even after one restart fails.

The deployment explicitly imports shared modules and the service. Configure
`homelab.storage.volumes`, persistent directories, the two Borg credential files,
Tailscale Serve, lifecycle units, backup job/schedule and health units/probe. Each
service gets a distinct Tailscale identity, Borg subaccount, repository, SSH key,
passphrase and `borg-<service-slug>` Document in the `Homelab` vault.

The deployment's common wiring is explicit. Use contract values rather than copying
literal paths or ports into the deployment:

```nix
homelab = {
  deployment = c;
  storage = {
    volumes = [ { path = c.persist.path; marker = c.persist.marker; } ];
    directories = [
      "/persist/secrets" "/persist/tailscale" "/persist/backup"
      "/persist/borg/config" "/persist/borg/cache" c.application.state
    ];
  };
  secrets.requiredFiles = [
    config.homelab.backup.passphraseFile
    config.homelab.backup.sshKeyFile
  ];
  tailscale.serveTarget = "http://127.0.0.1:${toString c.application.port}";
  lifecycle.units = [ "tailscaled" "tailscale-policy" "example-service" ];
  lifecycle.backupJob = "borgbackup-job-${config.homelab.backup.name}";
  backup = {
    enable = true;
    repositoryFile = "/persist/borg/repository";
    schedule = "SERVICE-SPECIFIC CALENDAR";
  };
  health = {
    units = [
      "homelab-operational.target" "storage-contract" "operational-ready"
      "tailscaled" "example-service"
    ];
    url = "http://127.0.0.1:${toString c.application.port}/READY_PATH";
  };
};
```

The quoted schedule and readiness path are review placeholders, not values that may
ship unchanged.

## Backup and restoration contract

`backup-prepare` must fail if quiescing is incomplete. Database-backed services
write an atomic logical dump and version record, exclude live database files, and
leave services stopped for Borg. `backup-cleanup` must be idempotent where practical,
attempt every restart, return failure if any restart fails and preserve the shared
recovery intent. Never initialize a repository automatically.

The service document must define selective archive paths, exclusions, ownership,
logical restore commands, integrity checks, manually startable restoration units,
identity-exclusivity rules and application acceptance tests. Rehearse restoration
to fresh recorded volumes before production use. The generic sequence is in
[recovery](recovery.md); service-specific steps must not be hidden in private notes.

## Required tests

At minimum, add:

- an evaluated service-configuration check and full system closure;
- backup-hook failure injection for successful quiesce, partial stop, Borg/prepare
  failure, restart failure and all-service restart attempts;
- listener/firewall, storage/readiness gating and upstream-target assertions;
- storage placement and layout tests for every multi-volume service;
- application-specific package, migration or hardware regression checks;
- an isolated backup/restore fixture appropriate to the state format.

Shared checks automatically cover runtime credentials, lifecycle wiring, mount
guards, image layout, release aggregation and repository topology. They do not
replace application-level recovery tests or a real disposable Proxmox rehearsal.

## Explicit registration and policy

Register the configuration, contract, `variant = "single"` catalog entry and
service check set in `flake.nix`. Flake assertions require all four registries to
have identical names and validate the common contract, versions JSON, lifecycle,
backup, secret, persist-volume and health wiring.

The four explicit registry additions have this shape:

```nix
example-service = mkContainer { deployment = ./deployments/example-service.nix; };
configurations = { inherit example-service; /* existing entries stay explicit */ };
contracts.example-service = import ./deployments/example-service-contract.nix;
imageCatalog.example-service = { service = "example-service"; variant = "single"; };
serviceCheckSets.example-service = import ./services/example-service/tests/checks.nix {
  inherit pkgs example-service;
};
```

Extend `provision/tailscale-policy.example.hujson` with the service tag owner,
administrator SSH/HTTPS access, intended user HTTPS access and positive/negative
policy tests. Keep real identities and addressing out of Git.

Add the service guide to the README, update architecture/operations documentation,
and add its current validation boundary. If image inputs change, bump `VERSION`
relative to main and update release notes before opening the PR. Verify an unrelated
service keeps the same image derivation, then run lint/evaluation locally and let
GitHub build every selected Linux check and image.

## Operator acceptance

Before activation, verify the explicit release and manifest, exact volume
provenance/markers, credential permissions, independently retrieved recovery
Document, repository access, isolated restoration and identity exclusivity. Activate
only with `homelab-activate`. Verify health, real login/workload behavior, the first
native backup and an independent restore before treating the service as protected.
