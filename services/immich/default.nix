{
  config,
  pkgs,
  lib,
  immichNixpkgs,
  ...
}:
let
  c = config.homelab.deployment;
  bootstrap = config.homelab.image.variant == "bootstrap";
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
{
  disabledModules = [ "services/web-apps/immich.nix" ];
  imports = [ (immichNixpkgs + "/nixos/modules/services/web-apps/immich.nix") ];
  config = lib.mkMerge [
    {
      environment.etc."homelab-versions.json".text = builtins.toJSON {
        immich = if bootstrap then null else config.services.immich.package.version;
        postgresql = if bootstrap then null else config.services.postgresql.package.version;
        contractVersion = c.contractVersion;
      };
    }
    (lib.mkIf (!bootstrap) {
      homelab.backup = {
        paths = [
          "/persist"
          "/data/immich"
        ];
        writablePaths = [
          "/persist"
          "/data/immich"
        ];
        excludes = [
          "/persist/postgresql"
          "/persist/borg/cache"
          "/persist/backup/immich.dump.tmp"
          # Legacy staging remains retained until explicit verified cleanup.
          "/persist/backup/immich-hot"
          "/persist/backup/redis"
        ];
        prepare = "${pkgs.bash}/bin/bash ${./backup-prepare}";
        cleanup = "${pkgs.bash}/bin/bash ${./backup-cleanup}";
      };
      systemd.services."borgbackup-job-${config.homelab.backup.name}".path =
        lib.mkIf config.homelab.backup.enable
          [
            config.services.postgresql.package
          ];
      environment.systemPackages = [
        pkgs.ffmpeg
        pkgs.libva-utils
      ];
      services.immich = {
        package = import ./package.nix {
          inherit immichNixpkgs;
          system = pkgs.stdenv.hostPlatform.system;
        };
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
        immich-machine-learning = gate // {
          environment.GUNICORN_CMD_ARGS = "--no-control-socket";
          environment.MACHINE_LEARNING_CPU_ONLY = "1";
          serviceConfig.LimitCORE = 0;
        };
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
          ${pkgs.bash}/bin/bash ${./layout} ${c.immichStorage.hot} ${c.immichStorage.bulk} ${toString c.immichUid} ${toString c.immichGid}
          install -d -m 0700 -o redis-immich -g redis-immich /persist/redis
        '';
      };
    })
    (lib.mkIf (config.homelab.image.variant == "recovery") {
      systemd.services.immich-server.wantedBy = lib.mkForce [ ];
      systemd.services.immich-machine-learning.wantedBy = lib.mkForce [ ];
      systemd.services.tailscale-policy.wantedBy = lib.mkForce [ ];
      homelab.backup.enable = lib.mkForce false;
    })
  ];
}
