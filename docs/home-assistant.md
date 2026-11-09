# Home Assistant and SLZB-MR4U setup

This deployment runs Home Assistant Core in an unprivileged NixOS LXC. It uses
ZHA with the MR4U's CC2674P10 radio. The EFR32MG26 remains uncommissioned so it
can be considered for Thread later. The Home Assistant LXC uses one `/persist`
volume and is accessed through Tailscale Serve.

## Before building an operator release

The operational image requires its own SOPS-encrypted Borg credentials. Keep
plaintext credentials out of Git, Nix, image inputs and command-line arguments.
Enroll the service's age identity, dedicated Borg repository, SSH key/passphrase,
and independently authenticated SSH host key as described in
[backup and recovery](recovery.md). Do not reuse Immich's backup identity or
repository. The operational readiness gate intentionally refuses to start HA
until enrollment is complete. The bootstrap image is for initial enrollment and
does not start Home Assistant or scheduled backups.

The contract proposes CT IDs 210/211, 2 cores, 4 GiB RAM, 32 GiB root, and one
32 GiB `/persist` volume. These are proposals, not allocations. Check the private
operator inventory and obtain the bounded deployment plan approval required by
`AGENTS.md` before production provisioning. The LXC needs a stable LAN address for
the MR4U's socket whitelist. Record the actual address privately; do not add it to
this repository.

The code registers `home-assistant`, `home-assistant-bootstrap`, and
`home-assistant-recovery` images in the flake. Build and release them through the
normal PR, required checks, exact-main release workflow and attestation checks.
Do not import a local development build into production.

## MR4U initial setup

The inspected device is reachable at `192.168.1.2`, running SLZB-OS `v3.2.4`.
Ethernet is connected with DHCP, IPv6/Wi-Fi/VPN/DDNS/MQTT are off. Both radio
coordinator sockets are configured but have no clients. Radio 1 is EFR32MG26 on
6638 (firmware `20240602`); radio 2 is CC2674P10 on 7638 (firmware `20240716`).
Automatic Zigbee firmware updates are currently on. Web authentication, socket
whitelisting and fallback AP password protection are currently off. Analytics is
currently allowed. All reported radio/core temperatures were about 35–37°C.

Before joining Zigbee devices:

1. In **Settings and Tools → Firmware update**, switch off **Zigbee Automatic
   Update** and save. Leave updates manual. Do not install firmware during setup.
2. In **Security**, enable **web server authentication** and set a unique strong
   device password. Store it in the private operator vault. Keep **Disable web
   server when socket is connected** off so the SMLIGHT integration can monitor
   the device while ZHA uses the radio socket.
3. Enable **fallback Wi-Fi AP password** and set a distinct strong password.
4. Leave **Enable IP whitelist for socket** off until the HA LXC has its final
   reserved LAN address. Then enable it with only that address and save.
5. Optionally disable non-sensitive analytics in **General settings**.
6. Leave radio 1 on its current firmware and ensure no Zigbee client is pointed at
   port 6638. Do not enable Zigbee Hub, Wi-Fi bridge, VPN, or automatic update.
7. Confirm the radio 2 values remain coordinator, Ethernet, TCP 7638, 115200 baud,
   and no hardware flow control. Do not use IEEE read/write tools; they interrupt
   an active socket and can split Zigbee identity.

The device serves management over plain HTTP on the LAN. Keep it on the trusted
LAN, use a unique password, and do not forward its web or socket ports from the
router. SMLIGHT documents the MR-series radio sockets as 6638 and 7638 and supports
an IP whitelist for the coordinator socket. Home Assistant will connect to
`192.168.1.2:7638`; management uses ports 80 and 81.

## Home Assistant first boot

1. Boot the reviewed operational image with the exact `/persist` volume and marker.
   Verify `storage-contract.service`, `operational-ready.service`, `tailscaled`,
   and `home-assistant` are active. The health URL is local `127.0.0.1:8123/api/`.
2. Enroll the intended Tailscale identity and verify `https://<container-tailnet-name>`
   works. Confirm port 8123 remains unreachable from the physical LAN.
3. Complete the Home Assistant owner account onboarding. Use a unique password
   and store it in the private operator vault.
4. In **Settings → Devices & services → Add integration**, add **Zigbee Home
   Automation (ZHA)** manually. Set radio type **Texas Instruments ZNP** and
   serial URL `socket://192.168.1.2:7638`. Use 115200 baud and no flow control.
   Confirm the shown adapter is CC2674P10 before creating the network. Do not
   configure the EFR32MG26 / 6638 endpoint.
5. Choose a Zigbee channel after checking local Wi-Fi channel use. Prefer 15, 20,
   or 25 when compatible with the local RF environment. Treat the channel as a
   migration choice once devices join.
6. After ZHA creates its network, make a manual network backup from ZHA's network
   settings. Confirm the automatic backup is also present. These backups include
   network security material and must remain inside `/persist` and encrypted Borg.
7. Add **SMLIGHT SLZB** separately from **Settings → Devices & services**. Enter
   host `192.168.1.2` and the device username/password in the UI. This integration
   monitors and manages the adapter; it does not replace ZHA's serial connection.
   Keep firmware and restart entities manual and restricted to administrators.
8. Pair one nearby mains-powered router first, then add devices. Verify real
   commands, availability, and the network map before expanding the mesh.

Home Assistant's SMLIGHT integration needs the standard management event stream;
do not enable the MR4U setting that moves SSE to port 80, since the device UI
explicitly says that disables SMLIGHT integration compatibility.

## Backup and recovery

Operational Borg runs daily at 01:30 Europe/Zurich, ahead of Immich's schedule.
It takes the operation lock, records restart intent, stops HA and Tailscale, backs
up `/persist` directly, applies retention, then attempts to restart both services.
If either restart fails, the backup job must retain recovery intent and alert the
operator. HA stays offline for the full Borg operation. The job excludes only the
reproducible Borg cache and incomplete temporary HA backup artifacts. Default
retention is daily 7, weekly 4, monthly 6.

Before MR4U firmware, radio mode, port, IEEE, or channel changes:

1. Confirm the last Borg archive is recent and independently restorable.
2. Create and verify a fresh manual ZHA network backup.
3. Run a manual Borg backup and verify the archive/check result.
4. Record MR4U core/radio firmware and radio identity in the private inventory.
5. Change one thing, then verify ZHA reconnects to the same network and devices
   respond. Do not update both radios or both firmware layers together.

If HA state is lost but the MR4U remains intact, restore `/persist` into a fresh,
verified volume and reconnect ZHA to port 7638. If the MR4U/radio is lost, keep the
old unit powered off and use ZHA's migration flow with the latest network backup.
If prompted, preserve the radio IEEE identity. Never operate two coordinators at
once with the same IEEE address. Rehearse restoration to fresh disposable volumes
and replacement hardware before calling the backup plan proven.

Do not enable scheduled backups until the separate repository is initialized,
credential escrow has been independently retrieved and tested, and a manual
backup/restore rehearsal passes. The shared health check deliberately reports
backup-unconfigured as unhealthy until those steps are complete.
