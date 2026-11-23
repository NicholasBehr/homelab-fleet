# Proposed resources only; live allocation requires a bounded operator plan.
{
  service = "paperless-ngx";
  architecture = "x86_64-linux";
  hostname = "paperless-ngx";
  initialId = 230;
  replacementId = 231;
  cores = 4;
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
    sizeGiB = 256;
    path = "/persist";
    marker = "homelab-paperless-ngx-persist-v1";
  };
  application = {
    state = "/persist/paperless";
    data = "/persist/paperless/data";
    media = "/persist/paperless/media";
    consume = "/persist/paperless/consume";
    port = 28981;
    uid = 1140;
    gid = 1140;
    settingsFile = "/persist/secrets/paperless.env";
  };
  postgresUid = 71;
  postgresGid = 71;
  redisUid = 1141;
  redisGid = 1141;
  uidOffset = 100000;
  gidOffset = 100000;
  tunDevice = "/dev/net/tun";
  contractVersion = 1;
}
