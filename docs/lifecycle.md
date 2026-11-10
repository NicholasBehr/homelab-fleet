# One image, explicit activation

Each service has one release output: `immich` or `home-assistant`. The same image
supports first enrollment, restoration and normal operation. Fresh roots have
`homelab-operational.target` disabled. Storage checks run, but application services,
databases, Tailscale and scheduled backup timers have no automatic boot links.
Missing/unsafe credentials fail readiness before protected services start.

There is no mode command, persistent activation marker or version-based activation.
State files and format markers on `/persist` describe data; they do not authorize
startup. Application/database compatibility still requires operator review.

## Standard controls

Use the authenticated Proxmox console (`pct enter ID`) during enrollment and
restoration. The target groups the application, database dependencies, Tailscale
and backup timer. Each member has `PartOf=homelab-operational.target`, so stopping
the target stops its members. Database helpers remain available for explicit
`systemctl start` during restoration; this is an operator action, not an automatic
mode transition. Do not independently enable member units or start applications
while restoring their state.

```sh
# Inspect without starting anything.
systemctl is-enabled homelab-operational.target
systemctl is-active homelab-operational.target

# After enrollment/restoration and verification: activate now and on this root's
# subsequent boots. Tailscale identity exclusivity must already be established.
systemctl enable --now homelab-operational.target
```

Before activation, initialize only the approved new Borg repository or verify the
existing repository, independently retrieve its 1Password Document, and complete
the required restore rehearsal. First enrollment may start `tailscaled` explicitly
through the console after credentials pass readiness, then use interactive
`tailscale up` with the approved tag. Never start restored Tailscale state until
the original instance is definitively stopped and restoration is complete.

The timer starts on activation and can run immediately if its calendar event was
missed. A Borg job has `Requisite=homelab-operational.target` and `After=` that
target: a manual timer/job request cannot activate the workload during restoration.
Backup cleanup refuses to restart services when the operational target is no
longer active and retains recovery intent for operator inspection.

To stop for restoration/replacement, stop the service's backup timer first and
wait for any running backup to finish. Then use the console:

```sh
systemctl disable --now homelab-operational.target
```

This stops Tailscale SSH too. Verify each member is stopped; services manually
started during restoration must also be stopped before extraction or cutover.
If activation fails, disable/stop the target, inspect individual unit results,
repair enrollment and verify again. Never interpret an enabled link as a health
check. `health-check` additionally requires the application, tailnet and recent
successful backup.

## Replacement and restoration

Enablement is a local symlink under `/etc/systemd/system`, on the disposable root.
It survives ordinary reboot but is absent from a newly imported root. Borg archives
`/persist` and declared data, not root enablement. Restoring all persistent data
therefore cannot activate a fresh root. Verify the target is disabled and inactive
before extraction; keep the original stopped before restoring its identity.

Use the exact compatible release for application restoration. On the same image,
start only the database and directory helpers needed for logical restoration,
verify data and credentials, stop those helpers, then activate the target. A second
root replacement between recovery and operation is unnecessary. Keep historical
bootstrap/recovery artifacts available for historical releases; new releases no
longer publish those output names.

## NixOS unit-directory adaptation

NixOS normally links `/etc/systemd/system` wholesale to its immutable generated
tree. `modules/lifecycle.nix` disables that one directory link and materializes the
same tree as directories with immutable unit-file links during activation. Existing
root-local enablement links survive reboot; unit contents still come from the
reviewed image. This supports ordinary `systemctl enable/disable` without a custom
mode tool or a writable `/etc` overlay. Unexpected legacy directory symlinks fail
activation; install a fresh root instead of modifying an old production root.

The adaptation assumes the repository's disposable-root replacement policy;
routine in-place rebuilds are unsupported. The Linux lifecycle boot test covers
initial inactivity, enrollment without activation, isolated dependency startup,
activation failure, standard enable/disable, timer/job isolation and reboot
persistence. Remove this adaptation if upstream NixOS supplies a supported mutable
unit-enablement directory with equivalent tested behavior.
