{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.backup;
  cleanupScript = pkgs.writeShellScript "backup-cleanup" ''
    set -euo pipefail
    owner=/run/homelab-backup/owner
    # A failed lock acquisition must not recover a different operation's services.
    test -s "$owner" || exit 0
    test "$(cat "$owner")" = "''${INVOCATION_ID:?systemd invocation required}" || exit 0
    exec 9>/persist/operation.lock
    ${pkgs.util-linux}/bin/flock -n 9
    ${cfg.cleanup}
    rm "$owner"
  '';
in
{
  options.homelab.backup = {
    name = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
    };
    enable = lib.mkEnableOption "per-service Borg backup (unconfigured until Storage Box enrollment)";
    repository = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    remotePath = lib.mkOption {
      type = lib.types.str;
      default = "borg-1.4";
    };
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/persist" ];
    };
    writablePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/persist" ];
    };
    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/persist/borg/cache" ];
    };
    passphraseFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/borg-passphrase";
    };
    sshKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/borg-ssh-key";
    };
    knownHostsFile = lib.mkOption {
      type = lib.types.str;
      default = "/persist/borg/known_hosts";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 02:15:00";
    };
    retention = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {
        daily = 7;
        weekly = 4;
        monthly = 6;
      };
    };
    prepare = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };
    cleanup = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repository != "";
        message = "Set an enrolled Borg repository";
      }
    ];
    services.borgbackup.jobs.${cfg.name} = {
      repo = cfg.repository;
      wrapper = "borg-job-${cfg.name}";
      paths = cfg.paths;
      exclude = cfg.excludes;
      doInit = false;
      failOnWarnings = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.passphraseFile}";
      };
      environment = {
        BORG_RSH = "${pkgs.openssh}/bin/ssh -i ${cfg.sshKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${cfg.knownHostsFile}";
        BORG_CONFIG_DIR = "/persist/borg/config";
        BORG_CACHE_DIR = "/persist/borg/cache";
      };
      extraArgs = [ "--remote-path=${cfg.remotePath}" ];
      startAt = cfg.schedule;
      prune.keep = cfg.retention;
      readWritePaths = cfg.writablePaths ++ [ "/run/homelab-backup" ];
      preHook = ''
        exec 9>/persist/operation.lock
        ${pkgs.util-linux}/bin/flock -n 9
        test ! -e /run/homelab-backup/owner || { echo 'Unresolved backup recovery intent' >&2; exit 1; }
        printf '%s' "''${INVOCATION_ID:?systemd invocation required}" > /run/homelab-backup/owner
        ${cfg.prepare}
      '';
      postHook = ''
        exec 9>&-
        ${cleanupScript} || exitStatus=1
      '';
    };
    systemd.services."borgbackup-job-${cfg.name}" = {
      requires = [
        "storage-contract.service"
        "operational-ready.service"
      ];
      after = [
        "storage-contract.service"
        "operational-ready.service"
      ];
      serviceConfig.RuntimeDirectory = "homelab-backup";
      serviceConfig.RuntimeDirectoryPreserve = "yes";
      path = [
        pkgs.systemd
        pkgs.util-linux
        pkgs.coreutils
      ];
      # Cleanup also runs after systemd terminates the job, including prepare failure.
      serviceConfig.ExecStopPost = cleanupScript;
    };
  };
}
