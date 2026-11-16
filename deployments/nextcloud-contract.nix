# Proposed resources only; live allocation requires a bounded operator plan.
{
  service = "nextcloud";
  architecture = "x86_64-linux";
  hostname = "nextcloud";
  initialId = 220;
  replacementId = 221;
  cores = 2;
  memoryMiB = 4096;
  swapMiB = 0;
  bridge = "vmbr0";
  network = "name=eth0,bridge=vmbr0,ip=dhcp,ip6=manual,firewall=1";
  root = {
    storage = "local-zfs";
    sizeGiB = 32;
  };
  persist = {
    slot = "mp0";
    storage = "local-zfs";
    sizeGiB = 128;
    path = "/persist";
    marker = "homelab-nextcloud-persist-v1";
  };
  data = {
    slot = "mp1";
    storage = "local-zfs";
    # 932 GiB is approximately 1 decimal TB; quota, not reserved capacity.
    sizeGiB = 932;
    path = "/data";
    marker = "homelab-nextcloud-data-v1";
  };
  application = {
    state = "/persist/nextcloud";
    data = "/data/nextcloud";
    temporary = "/data/nextcloud-tmp";
    port = 8080;
    uid = 1130;
    gid = 1130;
    settingsFile = "/persist/secrets/nextcloud-settings.json";
  };
  postgresUid = 71;
  postgresGid = 71;
  uidOffset = 100000;
  gidOffset = 100000;
  tunDevice = "/dev/net/tun";
  contractVersion = 1;
}
