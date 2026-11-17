# Home Assistant, Zigbee2MQTT and SLZB-MR4U

This single unprivileged NixOS LXC runs Home Assistant Core, a loopback-only
Mosquitto broker and Zigbee2MQTT. Zigbee2MQTT owns the MR4U CC2674P10 radio over
wired TCP 7638 and publishes Home Assistant MQTT discovery. The EFR32MG26 radio
on port 6638 remains uncommissioned for a later Thread/OTBR design.

Home Assistant binds `127.0.0.1:8123`, Mosquitto binds `127.0.0.1:1883`, and the
Zigbee2MQTT frontend binds `127.0.0.1:8080`. Tailscale Serve publishes Home
Assistant at `/` and Zigbee2MQTT at `/zigbee2mqtt`; none of these listeners is
opened on the physical LAN.

Open `https://<container-tailnet-name>/` for Home Assistant and
`https://<container-tailnet-name>/zigbee2mqtt` for Zigbee2MQTT. Mosquitto is an
MQTT broker without a web management page; its listener stays on loopback for
these applications.

## Release and runtime settings

Build the one `home-assistant` image through the normal PR, required-check,
exact-main release and attestation workflow. The proposed CT IDs and storage in
the deployment contract are not allocations; check the private inventory and
obtain the bounded production plan approval required by `AGENTS.md`.

Enroll the dedicated Borg repository and its root-only credential files as
described in [backup and recovery](recovery.md). Store and independently verify
the tagged `borg-home-assistant` Document in the `Homelab` vault. Do not reuse
another service's repository or identity.

With `/persist` mounted, enroll the privately inventoried MR4U endpoint in the
normal root-only runtime settings file `/persist/secrets/zigbee2mqtt.env`
(root:root, mode0600):

```text
ZIGBEE2MQTT_CONFIG_SERIAL_PORT=tcp://<MR4U-tailnet-or-LAN-address>:7638
```

Use an address reachable from this container. No custom enrollment program or
network-key file is required. On first activated start, Zigbee2MQTT generates
and persists the network key, PAN ID and extended PAN ID in its own configuration.
The service preserves that file on later starts so the identity remains stable.
Back it up with `/persist/zigbee2mqtt`; never restore it while another instance
can own the same Zigbee network or coordinator.

These settings and state belong in encrypted Borg. Never put secret values in
chat, clipboard, Git, image inputs or shell arguments. The separate
`borg-home-assistant` recovery Document retains its Borg-only schema.

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

## Fresh deployment

Deploy a new container with a new, provenance-verified `/persist` volume. Do not
restore or attach the old Home Assistant state, Zigbee database or network
backup. The only handoff requirement is to stop the old container and prove it
cannot reach the coordinator before the new Zigbee2MQTT instance connects to
port 7638. Never run both radio owners at once.

This intentionally creates a new Home Assistant instance and Zigbee network.
Factory-reset and pair only the Hue light and SR-ZG9002KR12-Pro switch. Configure
their names, areas and the switch automation again in the new instance.

## First activation

Boot the verified image with the exact new enrolled `/persist` volume. Fresh roots
remain inactive until `homelab-activate` creates their root-local activation
record. Activation verifies storage and Borg credentials, then starts Mosquitto,
Zigbee2MQTT and Home Assistant in dependency order. The coordinator endpoint
file must be installed before activation.

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
5. Open joining for a bounded interval in Zigbee2MQTT. Factory-reset and pair the
   mains-powered Hue light first, then the SR-ZG9002KR12-Pro switch. Name both
   devices and close joining. Verify every button and rotary action before
   creating the switch automation.
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
