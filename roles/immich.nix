{
  config,
  pkgs,
  lib,
  bootstrap,
  ...
}:
let
  c = import ../provision/containers.nix;
  gate = {
    requires = [
      "storage-contract.service"
      "operational-ready.service"
    ];
    after = [
      "storage-contract.service"
      "operational-ready.service"
    ];
  };
in
lib.mkIf (!bootstrap) {
  homelab.backup = {
    paths = [
      "/persist"
      "/data/.backup-stage"
    ];
    writablePaths = [
      "/persist"
      "/data/.backup-stage"
    ];
    excludes = [
      "/persist/immich"
      "/persist/postgresql"
      "/persist/redis"
      "/persist/borg/cache"
    ];
    prepare = "${pkgs.bash}/bin/bash ${../scripts/backup-prepare}";
    cleanup = "${pkgs.bash}/bin/bash ${../scripts/backup-cleanup}";
  };
  systemd.services.borgbackup-job-immich.path = lib.mkIf config.homelab.backup.enable [
    config.services.postgresql.package
  ];
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    mediaLocation = c.immichStorage.hot;
    accelerationDevices = [ c.renderDevice ];
    settings.ffmpeg = {
      accel = "qsv";
      accelDecode = true;
    };
  };
  users.users.immich = {
    uid = c.immichUid;
    extraGroups = [ "render" ];
  };
  users.groups.immich.gid = c.immichGid;
  users.users.postgres.uid = c.postgresUid;
  users.groups.postgres.gid = c.postgresGid;
  users.users.redis-immich.uid = c.redisUid;
  users.groups.redis-immich.gid = c.redisGid;
  services.postgresql = {
    package = pkgs.postgresql_17;
    dataDir = "/persist/postgresql/17";
    enableTCPIP = false;
  };
  services.redis.servers.immich = {
    settings.dir = lib.mkForce "/persist/redis";
  };
  systemd.services = {
    postgresql = gate;
    postgresql-setup = gate;
    immich-server = gate // {
      environment.LIBVA_DRIVER_NAME = "iHD";
    };
    immich-machine-learning = gate;
    redis-immich = gate // {
      serviceConfig.ReadWritePaths = [ "/persist/redis" ];
    };
  };
  # Only initialize the media directory after the storage gate, never tmpfiles.
  systemd.services.immich-directories = {
    inherit (gate) requires after;
    before = [
      "immich-server.service"
      "redis-immich.service"
      "postgresql.service"
    ];
    requiredBy = [
      "immich-server.service"
      "redis-immich.service"
      "postgresql.service"
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 0700 -o postgres -g postgres /persist/postgresql /persist/postgresql/17
      ${pkgs.bash}/bin/bash ${../scripts/immich-layout} ${c.immichStorage.hot} ${c.immichStorage.bulk} ${toString c.immichUid} ${toString c.immichGid}
      install -d -m 0700 -o redis-immich -g redis-immich /persist/redis
    '';
  };
  environment.etc."homelab-versions.json".text = builtins.toJSON {
    immich = config.services.immich.package.version;
    postgresql = config.services.postgresql.package.version;
    contractVersion = c.contractVersion;
  };
}
