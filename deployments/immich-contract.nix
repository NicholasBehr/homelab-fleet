# Authoritative proposed deployment contract; allocations require approval.
{
  service = "immich";
  architecture = "x86_64-linux";
  hostname = "immich";
  initialId = 200;
  replacementId = 201;
  cores = 2;
  memoryMiB = 6144;
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
    marker = "homelab-immich-persist-v1";
  };
  media = {
    slot = "mp1";
    storage = "local-zfs"; # initially NVMe; only this volume may move to hddpool
    sizeGiB = 512;
    path = "/data";
    marker = "homelab-immich-media-v1";
  };
  immichStorage = {
    hot = "/persist/immich";
    bulk = "/data/immich";
  };
  renderDevice = "/dev/dri/renderD128"; # verified PCI 0000:00:02.0, 8086:4680
  renderGid = 303;
  immichUid = 1100;
  immichGid = 1100;
  postgresUid = 71;
  postgresGid = 71;
  redisUid = 1101;
  redisGid = 1101;
  uidOffset = 100000;
  gidOffset = 100000;
  tunDevice = "/dev/net/tun";
  contractVersion = 2;
}
