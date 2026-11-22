# Proposed resource contract; allocations require a private inventory check.
{
  service = "jellyfin";
  architecture = "x86_64-linux";
  hostname = "jellyfin";
  initialId = 230;
  replacementId = 231;
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
    marker = "homelab-jellyfin-persist-v1";
  };
  media = {
    slot = "mp1";
    storage = "hddpool";
    sizeGiB = 10240;
    path = "/data";
    marker = "homelab-jellyfin-media-v1";
  };
  application = {
    state = "/persist/jellyfin";
    port = 8096;
    uid = 1140;
    gid = 1140;
    movies = "/data/media/movies";
    tv = "/data/media/tv";
    stagingMovies = "/data/staging/movies";
    stagingTv = "/data/staging/tv";
    rcloneConfigFile = "/persist/secrets/rclone.conf";
    rcloneKnownHostsFile = "/persist/secrets/rclone_known_hosts";
    rcloneRemote = "source";
    remoteMovies = "movies";
    remoteTv = "tv";
  };
  renderDevice = "/dev/dri/renderD128";
  renderGid = 303;
  uidOffset = 100000;
  gidOffset = 100000;
  tunDevice = "/dev/net/tun";
  contractVersion = 1;
}
