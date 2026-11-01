# Observed baseline and approval plan

Read-only discovery on 2026-11-01 found:
- Proxmox 9.2.24, kernel 7.0.14-26-pve, i5-14500, no containers.
- Operator confirms reset complete and Secure Boot intentionally disabled for now;
  enabling it later is a separate approved host operation. Preserve support for it.
- Intel PCI 0000:00:02.0, vendor/device 8086:4680, i915. renderD128 resolves to
  this PCI device. ASPEED card1 is a separate display adapter; do not pass it.
- vmbr0 on nic3, host 192.168.1.55/24, default gateway 192.168.1.1.
- local-zfs -> rpool/data (~3.51 TiB available), hddpool (~14.4 TiB available).
  hddpool currently permits images only. No change is needed for initial NVMe provisioning.
  Operator identifies local-zfs as NVMe RAID10 and hddpool as three-HDD RAIDZ1.
- local permits vztmpl. Default subordinate UID and GID ranges: root:100000:65536.
- pveproxy 8006 binds 127.0.0.1; Serve HTTPS binds Tailscale addresses.
- sshd 22 and rpcbind 111 bind all interfaces. Firewall enabled/running, cluster
  input DROP, node rules accept tailscale0 TCP443 and UDP41641 then drop input.
  Socket discovery does not prove LAN reachability. Verify from a separate LAN
  device and inspect effective rules/counters before concluding exposure is closed.

## Rehearsal first

The initial boot failure, successful nesting retry and subsequent replacement
results are in [rehearsal.md](rehearsal.md). CT990–994 now exist and are stopped;
all test storage is retained. Bootstrap replacement and missing/wrong-volume guards
passed, as did synthetic VA-API encoding/decoding with the planned Unix IDs.
The corrected releases passed TUN0600 and discovery-listener checks; synthetic
H.264/HEVC QSV passed under Immich account/hardening settings. Nesting
is not yet approved for the production service contract.
The pre-test read-only refresh confirmed CT990/991 were free and local-zfs had ~3.51 TiB free,
and the render device still belongs to Intel PCI 0000:00:02.0. Installed Proxmox
provides a native `nixos` setup plugin that writes networkd/DNS configuration;
`unmanaged` skips that setup. Provisioning/replacement runbooks now use `nixos`.
These are host-side setup semantics; the published image is unchanged.

## Proposed eventual service batch, NOT executed

Prerequisites: successful CI, verified immutable bootstrap artifact, approved
capacities/IDs, LAN reachability test, local console recovery available.

1. Download the verified artifact to local template storage as in provisioning.
2. Create CT200 with 32 GiB root, 256 GiB persist and 512 GiB bulk data, all on local-zfs,
   with 6 cores/12 GiB RAM,
   DHCP vmbr0, dev0 render mode0660 root:303, dev1 TUN mode0600 root:root.
3. Mount stopped CT200, initialize only new volume-root ownership and marker files,
   unmount and start it. Exact commands: docs/provisioning.md.
4. Through pct console, generate age key and enroll Tailscale. Each is a host
   mutation through pct exec/enter and must be included in approval.

Recovery: stop CT200, retain all volumes and configuration. No deletion command
is part of this batch. No storage capability changes are needed initially. Persist/data sizes are quotas,
not reservations (verified from the installed ZFSPoolPlugin and parent properties); backup staging uses additional allocated
media space. Get approval before changing any proposed capacity.

The disposable CT990/991 transfer test has passed. Future test iterations and
cleanup follow AGENTS.md: verify exact creation records, GUIDs, all attachments
and disposable data classification before storage mutations. The current record
is [test-resources.json](test-resources.json). Never infer permission from a test
container ID or attachment alone; production/recovery data and sole backups are
excluded. Never test deletion on CT200/201.

Host listener hardening is a separate batch after effective firewall and LAN
checks. Do not disable host sshd or rpcbind until Tailscale SSH and physical console
recovery are verified. No driver, package, firewall, storage, firmware or daemon
change has been made by the implementation process.
