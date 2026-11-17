{
  config,
  lib,
  pkgs,
  ...
}:
let
  c = config.homelab.deployment;
  a = c.application;
  nc = config.services.nextcloud;
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
  active = gate // {
    unitConfig.ConditionPathExists = "/var/lib/homelab/operational-enabled";
    partOf = [ "homelab-operational.target" ];
  };
  occ = builtins.head (
    builtins.filter (p: lib.getName p == "nextcloud-occ") config.environment.systemPackages
  );
  directoryRules = pkgs.writeText "nextcloud-directories.conf" (
    lib.concatStringsSep "\n" (
      builtins.filter (
        rule: !(lib.hasPrefix "d ${a.state}/data " rule)
      ) config.homelab.nextcloud.directoryRules
    )
  );
  verifyVolumes = lib.concatMapStringsSep "\n" (
    v:
    "${pkgs.bash}/bin/bash ${../../scripts/verify-storage} ${lib.escapeShellArg v.path} ${lib.escapeShellArg v.marker}"
  ) config.homelab.storage.volumes;
in
{
  imports = [ ./upstream.nix ];
  options.homelab.nextcloud.directoryRules = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Upstream Nextcloud directory rules, executed only after volume verification.";
  };
  config = {
    environment.etc."homelab-versions.json".text = builtins.toJSON {
      nextcloud = nc.package.version;
      php = config.services.phpfpm.pools.nextcloud.phpPackage.version;
      postgresql = config.services.postgresql.package.version;
      contractVersion = c.contractVersion;
    };
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "nextcloud-initialize";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.util-linux
          pkgs.systemd
          config.services.postgresql.package
          occ
        ];
        text = verifyVolumes + "\n" + builtins.readFile ./initialize;
      })
    ];
    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud34;
      hostName = "localhost"; # Real tailnet name is runtime configuration, not image input.
      home = a.state;
      datadir = a.state;
      https = true;
      secretFile = a.settingsFile;
      database.createLocally = true;
      config = {
        dbtype = "pgsql";
        dbhost = "/run/postgresql";
        dbname = "nextcloud";
        dbuser = "nextcloud";
        adminuser = null;
        adminpassFile = null;
      };
      configureRedis = true;
      caching.apcu = true;
      appstoreEnable = false;
      autoUpdateApps.enable = false;
      maxUploadSize = "10G";
      fastcgiTimeout = 3600;
      nginx.enableFastcgiRequestBuffering = true;
      poolSettings = {
        "pm" = "dynamic";
        "pm.max_children" = 4;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 1;
        "pm.max_spare_servers" = 2;
        "request_terminate_timeout" = "3600s";
      };
      phpOptions = {
        "memory_limit" = lib.mkForce "512M";
        "upload_tmp_dir" = "${a.temporary}/php";
        "sys_temp_dir" = "${a.temporary}/php";
        "max_execution_time" = "3600";
        "max_input_time" = "3600";
      };
      settings = {
        datadirectory = a.data;
        tempdirectory = "${a.temporary}/php";
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
        overwriteprotocol = "https";
        default_phone_region = "CH";
        maintenance_window_start = 0;
        shareapi_allow_links = false;
        skeletondirectory = "";
        # Bound retained data independently of user file quotas.
        trashbin_retention_obligation = "auto, 30";
        versions_retention_obligation = "auto, 30";
      };
    };
    users.users.nextcloud = {
      uid = a.uid;
      createHome = lib.mkForce false;
    };
    users.groups.nextcloud.gid = a.gid;
    users.users.postgres.uid = c.postgresUid;
    users.groups.postgres.gid = c.postgresGid;
    services.postgresql = {
      package = pkgs.postgresql_17;
      dataDir = "/persist/postgresql/17";
      enableTCPIP = false;
    };
    systemd.targets.postgresql.wantedBy = lib.mkForce [ ];
    # Assert enrollment at activation without making normal backup stops tear
    # down the operational target (Requires=nginx would do exactly that).
    systemd.targets.homelab-operational.unitConfig.AssertPathExists = [
      "${a.state}/config/config.php"
      "${a.data}/.ncdata"
      "/persist/postgresql/17/PG_VERSION"
    ];
    services.redis.servers.nextcloud.settings = {
      dir = lib.mkForce "/persist/redis";
      save = lib.mkForce "\"\""; # Cache/locks only; never restore stale locks.
      appendonly = false;
    };
    services.nginx.virtualHosts.localhost = {
      listen = [
        {
          addr = "127.0.0.1";
          port = a.port;
        }
      ];
      default = true;
      extraConfig = ''
        access_log off;
        client_body_temp_path ${a.temporary}/nginx-body;
        fastcgi_temp_path ${a.temporary}/nginx-fastcgi;
        client_body_timeout 3600s;
      '';
    };
    systemd.services = {
      operational-ready.postStart = "${pkgs.python3}/bin/python3 ${./verify-settings.py} ${lib.escapeShellArg a.settingsFile}";
      nextcloud-directories = gate // {
        before = [
          "nextcloud-setup.service"
          "postgresql.service"
          "redis-nextcloud.service"
          "nginx.service"
          "phpfpm-nextcloud.service"
        ];
        requiredBy = [
          "nextcloud-setup.service"
          "postgresql.service"
          "redis-nextcloud.service"
          "nginx.service"
          "phpfpm-nextcloud.service"
        ];
        path = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${verifyVolumes}
          for directory in ${a.state} ${a.state}/config ${a.state}/config/config.php ${a.data} ${a.temporary} ${a.temporary}/php ${a.temporary}/nginx-body ${a.temporary}/nginx-fastcgi /persist/postgresql /persist/postgresql/17 /persist/redis; do
            test ! -L "$directory" || { echo 'Refusing symlinked state directory' >&2; exit 1; }
          done
          ${pkgs.systemd}/bin/systemd-tmpfiles --create ${directoryRules}
          install -d -m 0750 -o nextcloud -g nextcloud ${a.data}
          install -d -m 0755 -o root -g root ${a.temporary}
          install -d -m 0700 -o nextcloud -g nextcloud ${a.temporary}/php
          install -d -m 0700 -o nginx -g nginx ${a.temporary}/nginx-body ${a.temporary}/nginx-fastcgi
          install -d -m 0700 -o postgres -g postgres /persist/postgresql /persist/postgresql/17
          install -d -m 0700 -o nextcloud -g nextcloud /persist/redis
        '';
      };
      postgresql = gate // {
        # Only an explicit inactive-root helper session may create a new cluster.
        serviceConfig.ExecStartPre = lib.mkBefore [
          "+${pkgs.writeShellScript "nextcloud-postgresql-guard" ''
            if test -f /var/lib/homelab/operational-enabled; then
              test -f /persist/postgresql/17/PG_VERSION || { echo 'Restore PostgreSQL before activation' >&2; exit 1; }
            fi
          ''}"
        ];
      };
      postgresql-setup = gate;
      redis-nextcloud = gate // {
        serviceConfig.ReadWritePaths = [ "/persist/redis" ];
      };
      nextcloud-setup = active // {
        wants = lib.mkForce [ ]; # No implicit DB maintenance racing with backups.
        requires = [ "redis-nextcloud.service" ] ++ gate.requires;
        after = [ "redis-nextcloud.service" ] ++ gate.after;
        path = [ pkgs.jq ];
        # Do not install, delete app trees, or touch passwords on normal startup.
        script = lib.mkForce ''
          test -s ${a.state}/config/config.php || { echo 'Initialize or restore explicitly before activation' >&2; exit 1; }
          test -f ${a.data}/.ncdata || { echo 'Missing Nextcloud data marker' >&2; exit 1; }
          maintenance=$(${lib.getExe occ} config:system:get maintenance)
          restore_maintenance=0
          restore_maintenance_mode() {
            if (( restore_maintenance )); then
              ${lib.getExe occ} maintenance:mode --on || true
            fi
          }
          trap restore_maintenance_mode EXIT
          if test "$maintenance" = true || test "$maintenance" = 1; then
            ${lib.getExe occ} maintenance:mode --off
            restore_maintenance=1
          fi
          ${lib.getExe occ} upgrade
          if (( restore_maintenance )); then
            ${lib.getExe occ} maintenance:mode --on
            restore_maintenance=0
          fi
          trap - EXIT
          ${lib.getExe occ} background:cron
        '';
        serviceConfig.RemainAfterExit = true;
      };
      nextcloud-install = gate // {
        requires = [
          "nextcloud-directories.service"
          "postgresql-setup.service"
          "redis-nextcloud.service"
        ]
        ++ gate.requires;
        after = [
          "nextcloud-directories.service"
          "postgresql-setup.service"
          "redis-nextcloud.service"
        ]
        ++ gate.after;
        unitConfig.ConditionPathExists = "!/var/lib/homelab/operational-enabled";
        environment = {
          NC_setup_create_db_user = "false";
          NEXTCLOUD_CONFIG_DIR = "${a.state}/config";
        };
        path = [
          occ
          pkgs.findutils
          config.services.postgresql.package
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "nextcloud";
          UMask = "0077";
          LimitCORE = 0;
          LoadCredential = config.systemd.services.nextcloud-setup.serviceConfig.LoadCredential;
        };
        script = ''
          test ! -e ${a.state}/config/config.php
          test -z "$(find ${a.data} -mindepth 1 -print -quit)"
          test "$(psql -X -At --dbname=nextcloud -c "select count(*) from information_schema.tables where table_schema='public'")" = 0
          nextcloud-occ maintenance:install --database=pgsql --database-host=/run/postgresql \
            --database-name=nextcloud --database-user=nextcloud --database-pass= \
            --disable-admin-user --data-dir=${a.data}
          nextcloud-occ maintenance:mode --on
        '';
      };
      nextcloud-cron = active // {
        requires = [ "nextcloud-setup.service" ] ++ gate.requires;
        serviceConfig.KillMode = lib.mkForce "control-group";
      };
      nextcloud-update-db = active // {
        serviceConfig.KillMode = "control-group";
      };
      phpfpm-nextcloud = active // {
        requires = [ "nextcloud-setup.service" ] ++ gate.requires;
        after = [ "nextcloud-setup.service" ] ++ gate.after;
      };
      nginx = active // {
        serviceConfig.ReadWritePaths = [
          "${a.temporary}/nginx-body"
          "${a.temporary}/nginx-fastcgi"
        ];
        requires = [ "phpfpm-nextcloud.service" ] ++ gate.requires;
        after = [ "phpfpm-nextcloud.service" ] ++ gate.after;
      };
    };
    systemd.timers.nextcloud-cron = {
      wantedBy = lib.mkForce [ "homelab-operational.target" ];
      partOf = [ "homelab-operational.target" ];
      requires = [ "nextcloud-setup.service" ];
      after = [ "nextcloud-setup.service" ];
    };
    homelab.backup = {
      paths = [
        "/persist"
        a.data
      ];
      writablePaths = [
        "/persist"
        a.data
        a.temporary
      ];
      excludes = [
        "/persist/postgresql"
        "/persist/redis"
        "/persist/borg/cache"
        "/persist/backup/nextcloud.dump.tmp"
      ];
      prepare = verifyVolumes + "\n${pkgs.bash}/bin/bash ${./backup-prepare}";
      cleanup = "${pkgs.bash}/bin/bash ${./backup-cleanup}";
    };
    systemd.services."borgbackup-job-${config.homelab.backup.name}".path = [
      config.services.postgresql.package
      occ
      pkgs.jq
    ];
  };
}
