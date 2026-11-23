{
  config,
  lib,
  pkgs,
  paperlessNixpkgs,
  ...
}:
let
  c = config.homelab.deployment;
  a = c.application;
  paperlessPkgs = import paperlessNixpkgs { system = pkgs.stdenv.hostPlatform.system; };
  paperless = config.services.paperless;
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
  verifyVolumes = lib.concatMapStringsSep "\n" (
    v:
    "${pkgs.bash}/bin/bash ${../../scripts/verify-storage} ${lib.escapeShellArg v.path} ${lib.escapeShellArg v.marker}"
  ) config.homelab.storage.volumes;
in
{
  disabledModules = [ "services/misc/paperless.nix" ];
  imports = [ (paperlessNixpkgs + "/nixos/modules/services/misc/paperless.nix") ];

  config = {
    environment.etc."homelab-versions.json".text = builtins.toJSON {
      paperless-ngx = paperless.package.version;
      postgresql = config.services.postgresql.package.version;
      redis = config.services.redis.package.version;
      contractVersion = c.contractVersion;
    };

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "paperless-initialize";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.systemd
          pkgs.util-linux
          config.services.postgresql.package
          paperless.manage
        ];
        text = verifyVolumes + "\n" + builtins.readFile ./initialize;
      })
    ];

    services.paperless = {
      enable = true;
      package = paperlessPkgs.paperless-ngx;
      address = "127.0.0.1";
      port = a.port;
      dataDir = a.data;
      mediaDir = a.media;
      consumptionDir = a.consume;
      consumptionDirIsPublic = false;
      passwordFile = null;
      database.createLocally = true;
      configureNginx = false;
      configureTika = false;
      exporter.enable = false;
      tesseractLanguages = [
        "deu"
        "eng"
      ];
      settings = {
        PAPERLESS_OCR_LANGUAGE = "deu+eng";
        PAPERLESS_ARCHIVE_FILE_GENERATION = "auto";
        PAPERLESS_AI_ENABLED = false;
        PAPERLESS_ENABLE_UPDATE_CHECK = false;
      };
    };

    users.users.paperless = {
      uid = lib.mkForce a.uid;
      isSystemUser = true;
      createHome = lib.mkForce false;
    };
    users.groups.paperless.gid = lib.mkForce a.gid;
    users.users.postgres.uid = c.postgresUid;
    users.groups.postgres.gid = c.postgresGid;
    users.users.redis-paperless.uid = c.redisUid;
    users.groups.redis-paperless.gid = c.redisGid;

    services.postgresql = {
      package = pkgs.postgresql_17;
      dataDir = "/persist/postgresql/17";
      enableTCPIP = false;
    };
    systemd.targets.postgresql.wantedBy = lib.mkForce [ ];
    services.redis.servers.paperless.settings = {
      dir = lib.mkForce "/persist/redis";
      save = lib.mkForce "\"\"";
      appendonly = false;
    };

    # Upstream tmpfiles run before the volume gate. Stateful directories are
    # instead created by paperless-directories after exact mount verification.
    systemd.tmpfiles.settings."10-paperless" = lib.mkForce { };
    systemd.targets.homelab-operational.unitConfig.AssertPathExists = [
      "${a.state}/.initialized"
      "${a.data}/nixos-paperless-secret-key.env"
      "/persist/postgresql/17/PG_VERSION"
    ];

    systemd.services = {
      paperless-directories = gate // {
        before = [
          "paperless-secret-key.service"
          "paperless-scheduler.service"
          "paperless-task-queue.service"
          "paperless-consumer.service"
          "paperless-web.service"
          "postgresql.service"
          "redis-paperless.service"
        ];
        requiredBy = [
          "paperless-secret-key.service"
          "paperless-scheduler.service"
          "paperless-task-queue.service"
          "paperless-consumer.service"
          "paperless-web.service"
          "postgresql.service"
          "redis-paperless.service"
        ];
        path = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${verifyVolumes}
          for directory in ${a.state} ${a.data} ${a.data}/index ${a.media} ${a.consume} /persist/postgresql /persist/postgresql/17 /persist/redis; do
            test ! -L "$directory" || { echo 'Refusing symlinked Paperless state directory' >&2; exit 1; }
          done
          install -d -m 0700 -o paperless -g paperless ${a.state} ${a.data} ${a.data}/index ${a.media} ${a.consume}
          install -d -m 0700 -o postgres -g postgres /persist/postgresql /persist/postgresql/17
          install -d -m 0700 -o redis-paperless -g redis-paperless /persist/redis
        '';
      };

      postgresql = gate // {
        serviceConfig.ExecStartPre = lib.mkBefore [
          "+${pkgs.writeShellScript "paperless-postgresql-guard" ''
            if test -f /var/lib/homelab/operational-enabled; then
              test -f /persist/postgresql/17/PG_VERSION || { echo 'Restore PostgreSQL before activation' >&2; exit 1; }
            fi
          ''}"
        ];
      };
      postgresql-setup = gate;
      redis-paperless = gate // {
        serviceConfig.ReadWritePaths = [ "/persist/redis" ];
      };
      paperless-secret-key = gate;

      paperless-scheduler = active // {
        # Never let upstream's version file decide whether an empty database may
        # be initialized. Explicit initialization creates the schema and marker.
        preStart = lib.mkForce ''
          test -f ${a.state}/.initialized || { echo 'Initialize or restore Paperless before activation' >&2; exit 1; }
          test "$(${config.services.postgresql.package}/bin/psql -X -At --dbname=paperless -c "select to_regclass('public.documents_document') is not null")" = t || {
            echo 'Restore the Paperless database before activation' >&2; exit 1;
          }
          ${lib.getExe paperless.package} migrate
          ${lib.getExe paperless.package} document_index reindex --if-needed --no-progress-bar
        '';
        serviceConfig.EnvironmentFile = lib.mkAfter [ a.settingsFile ];
      };
      paperless-task-queue = active // {
        serviceConfig.EnvironmentFile = lib.mkAfter [ a.settingsFile ];
      };
      paperless-consumer = active // {
        serviceConfig.EnvironmentFile = lib.mkAfter [ a.settingsFile ];
      };
      paperless-web = active // {
        serviceConfig.EnvironmentFile = lib.mkAfter [ a.settingsFile ];
      };
      operational-ready.postStart = "${pkgs.python3}/bin/python3 ${./verify-settings.py} ${lib.escapeShellArg a.settingsFile}";
    };

    homelab.backup = {
      paths = [ "/persist" ];
      writablePaths = [ "/persist" ];
      excludes = [
        "/persist/postgresql"
        "/persist/redis"
        "/persist/borg/cache"
        "/persist/backup/paperless.dump.tmp"
      ];
      prepare = verifyVolumes + "\n${pkgs.bash}/bin/bash ${./backup-prepare}";
      cleanup = "${pkgs.bash}/bin/bash ${./backup-cleanup}";
    };
    systemd.services."borgbackup-job-${config.homelab.backup.name}".path = [
      config.services.postgresql.package
      pkgs.util-linux
    ];
  };
}
