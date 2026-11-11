# Proposed resource contract; allocations require a private inventory check.
{
  service = "home-assistant";
  architecture = "x86_64-linux";
  hostname = "home-assistant";
  initialId = 210;
  replacementId = 211;
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
    sizeGiB = 32;
    path = "/persist";
    marker = "homelab-home-assistant-persist-v1";
  };
  application = {
    state = "/persist/home-assistant";
    port = 8123;
    uid = 1102;
    gid = 1102;
  };
  uidOffset = 100000;
  gidOffset = 100000;
  tunDevice = "/dev/net/tun";
  contractVersion = 2;
}
