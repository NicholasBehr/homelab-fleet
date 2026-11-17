# Home Assistant, Zigbee2MQTT and SLZB-MR4U

This single unprivileged NixOS LXC runs Home Assistant Core, a loopback-only
Mosquitto broker and Zigbee2MQTT. Zigbee2MQTT owns the MR4U CC2674P10 radio over
wired TCP 7638 and publishes Home Assistant MQTT discovery. The EFR32MG26 radio
on port 6638 remains uncommissioned for a later Thread/OTBR design.

Home Assistant binds `127.0.0.1:8123`, Mosquitto binds `127.0.0.1:1883`, and the
Zigbee2MQTT frontend binds `127.0.0.1:8080`. Tailscale Serve publishes Home
Assistant at `/` and Zigbee2MQTT at `/zigbee2mqtt`; none of these listeners is
opened on the physical LAN.

## Release and runtime enrollment

Build the one `home-assistant` image through the normal PR, required-check,
exact-main release and attestation workflow. The proposed CT IDs and storage in
the deployment contract are not allocations; check the private inventory and
obtain the bounded production plan approval required by `AGENTS.md`.

Enroll the dedicated Borg repository and its root-only credential files as
described in [backup and recovery](recovery.md). Store and independently verify
the tagged `borg-home-assistant` Document in the `Homelab` vault. Do not reuse
another service's repository or identity.

With the intended `/persist` volume mounted on the inactive replacement root,
run this once from the protected root console:

```console
zigbee2mqtt-enroll
```

The helper verifies the storage marker, asks for the privately recorded MR4U DNS
name or IPv4 address and a fresh channel (11, 15, 20 or 25), then generates a
random network key, PAN ID and extended PAN ID without printing them. It creates
`/persist/secrets/zigbee2mqtt.env` and
`/persist/secrets/zigbee2mqtt.yaml` as root:root mode0600 and refuses to replace
existing enrollment. These files belong in encrypted Borg; never copy their
contents through chat, clipboard, Git, image inputs or shell arguments. The
separate `borg-home-assistant` recovery Document retains its Borg-only schema.

## MR4U configuration

Record the coordinator address, SLZB-OS version, radio firmware and radio
identity only in the private operator inventory. Keep Ethernet connected and
disable unused Wi-Fi, VPN, DDNS and on-device MQTT/Zigbee Hub features.

1. Disable automatic Zigbee firmware updates. Keep firmware changes manual.
2. Enable web authentication with a unique stored password and configure a
   separate fallback AP password.
3. Keep the web server available while the socket is connected so the SMLIGHT
   integration can monitor the adapter. Do not move SSE to port 80.
4. Keep the socket IP whitelist off unless a later network plan supplies a stable
   source identity. Do not forward management or coordinator ports at the router.
5. Configure the CC2674P10 as a Z-Stack coordinator over Ethernet, TCP 7638,
   115200 baud and no flow control. Only Zigbee2MQTT may own this socket.
6. Leave the EFR32MG26 / 6638 radio unused. Do not enable multiprotocol firmware,
   Zigbee Hub or OTBR as part of this change.

## Switching from ZHA

This release intentionally forms a fresh Zigbee2MQTT network. It does not convert
the ZHA device database, and every Zigbee device must be factory-reset and paired
again. Historical ZHA backups remain protected under Home Assistant state but do
not authorize startup or determine the new network identity.

Before replacing the root:

1. Make and retain a final manual ZHA network backup and a successful consistent
   Borg backup.
2. Record affected device names, areas and automations without exporting secrets
   or live radio identifiers into this repository.
3. Disable or remove the ZHA integration in Home Assistant while the old system
   is still available. The new image refuses activation while an active ZHA
   configuration entry remains, preventing two clients from racing for port7638.
4. Deactivate the old root and prove it cannot run before connecting the new
   Zigbee2MQTT instance. Never run both owners against the same coordinator.

## First activation

Boot the verified image with the exact enrolled `/persist` volume. Fresh roots
remain inactive until `homelab-activate` creates their root-local activation
record. Activation verifies storage, Borg credentials, the two Zigbee enrollment
files and absence of active ZHA before starting Mosquitto, Zigbee2MQTT and Home
Assistant in dependency order.

1. Verify `storage-contract`, `operational-ready`, `mosquitto`, `zigbee2mqtt`,
   `tailscaled` and `home-assistant` are active.
2. Open `https://<container-tailnet-name>/zigbee2mqtt`. Confirm the coordinator
   is the CC2674P10 on port 7638, the selected channel is correct, joining is
   closed, and a coordinator backup exists. Do not display its network key.
3. In **Settings → Devices & services**, add **MQTT** with broker
   `127.0.0.1`, port `1883`, and no username or password. The broker accepts
   anonymous clients only on loopback; it is unreachable from the LAN or tailnet.
4. Add **SMLIGHT SLZB** separately using the private coordinator host and device
   credentials. This monitors the MR4U; it does not own the serial socket.
5. Open joining for a bounded interval in Zigbee2MQTT, pair one nearby
   mains-powered router, then pair and name devices individually. Close joining
   after each session. Pair the SR-ZG9002KR12-Pro and verify every button and
   rotary action before recreating its automations.
6. Verify MQTT discovery, real commands, availability, automations and the mesh
   map. Take a manual Borg backup and perform an independent representative
   restore before normal use.

## Backup and recovery

The daily Borg job at 01:30 Europe/Zurich takes the operation lock and stops Home
Assistant, Zigbee2MQTT, Mosquitto and Tailscale for the full archive operation.
Cleanup attempts every required restart in dependency order even after a failure;
retained recovery intent keeps a failed restart visible. The archive covers all
of `/persist`, excluding only Borg cache and incomplete temporary Home Assistant
backup artifacts.

Restore into a fresh, correctly marked volume while the replacement root remains
inactive:

- `/persist/home-assistant`, including SQLite and `.storage`;
- `/persist/zigbee2mqtt`, including `database.db`, device/group configuration
  and `coordinator_backup.json`;
- `/persist/mosquitto` retained broker state;
- `/persist/secrets`, Borg configuration/trust and the repository endpoint;
- `/persist/tailscale` only after proving identity exclusivity.

Preserve the new outer volume marker. Verify Home Assistant state ownership
UID/GID1102, Zigbee2MQTT UID/GID1103, Mosquitto UID/GID1104 and root-only runtime
files before activation. Run SQLite integrity checking without printing rows.
Confirm the Zigbee2MQTT database and coordinator backup exist and agree with the
intended CC2674P10; do not inspect or report their secret values.

After proving the original Tailscale and Zigbee owners cannot run, activate the
replacement and verify HTTPS, login, MQTT discovery, coordinator connection,
real device commands and the Zigbee network identity. If the coordinator is lost,
keep the old unit powered off and restore the Zigbee2MQTT state and supported
coordinator backup to replacement hardware. Never operate duplicate coordinator
IEEE identities.

Before MR4U firmware, channel, radio mode, port or IEEE changes, require a recent
independently restorable Borg archive and fresh Zigbee2MQTT coordinator backup.
Change one layer at a time and verify the same network and real device commands
afterward. Thread enablement is a separate architecture and production plan.
