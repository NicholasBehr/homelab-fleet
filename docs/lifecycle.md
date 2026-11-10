# One image, explicit activation

Each service has one release output: `immich` or `home-assistant`. The same image
supports first enrollment, restoration and normal operation. The operational target
is added to the boot transaction by a systemd generator only when the root-local
activation record exists. On a fresh root, application services, databases,
Tailscale and scheduled backup timers remain inactive.
Missing/unsafe credentials fail readiness before protected services start.

`homelab-activate` and `homelab-deactivate` are narrow lifecycle commands. They
manage `/var/lib/homelab/operational-enabled` on the disposable root and the
systemd target; they do not inspect or mutate `/persist`. State files and format
markers on `/persist` describe data but never authorize startup. Application and
database compatibility still require operator review.

## Standard controls

Use the authenticated Proxmox console (`pct enter ID`) during enrollment and
restoration. The target groups the application, database dependencies, Tailscale
and backup timer. Each member has `PartOf=homelab-operational.target`, so stopping
the target stops its members. Database helpers remain available for explicit
`systemctl start` during restoration; this is an operator action, not an automatic
mode transition. Do not independently enable member units or start applications
while restoring their state.

The target requires storage and credential readiness, and wants its workload
members. A temporary member stop during a quiesced backup must not stop the target
itself. Member health is checked independently; target activation is not proof of
application health. Explicit manual starts bypass the boot gate; operators use
those only for the documented enrollment or restoration steps.

```sh
# Inspect without starting anything.
test -e /var/lib/homelab/operational-enabled
systemctl is-active homelab-operational.target

# After enrollment/restoration and verification: activate now and on this root's
# subsequent boots. Tailscale identity exclusivity must already be established.
homelab-activate
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
homelab-deactivate
```

This stops Tailscale SSH too. Verify each member is stopped; services manually
started during restoration must also be stopped before extraction or cutover.
If activation fails, the command removes the activation record and stops the target.
Inspect individual unit results, repair enrollment and verify again. Never interpret
the activation record as a health check. `health-check` additionally requires the
application, tailnet and recent successful backup.

## Replacement and restoration

Enablement is a root-owned record under `/var/lib/homelab` on the disposable root.
It survives ordinary reboot but is absent from a newly imported root. Borg archives
`/persist` and declared data, not this root-local record. Restoring all persistent data
therefore cannot activate a fresh root. Verify the activation record is absent and
the target inactive before extraction; keep the original stopped before restoring
its identity.

Use the exact compatible release for application restoration. On the same image,
start only the database and directory helpers needed for logical restoration,
verify data and credentials, stop those helpers, then activate the target. A second
root replacement between recovery and operation is unnecessary. Keep historical
bootstrap/recovery artifacts available for historical releases; new releases no
longer publish those output names.

## NixOS lifecycle model

NixOS owns the declarative systemd unit tree; this design does not replace or make
that tree mutable. An early systemd generator adds a transient link under
`/run/systemd/generator` only when the disposable-root record exists. On a fresh
image, neither the target nor any of its dependencies enters the boot transaction.
Activation writes the record atomically, reloads systemd generators and starts the
target; failed startup removes the record and reloads again. Deactivation removes
the record and reloads before stopping the target, so even an interrupted stop
cannot reactivate on reboot.

Routine in-place rebuilds remain unsupported. The Linux lifecycle boot test covers
initial inactivity, enrollment without activation, isolated dependency startup,
activation failure, backup quiesce/restart, repeated activation/deactivation without
reboot, timer/job isolation and reboot persistence.
