{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.backup;
  runtimeRepository = cfg.repositoryFile != null;
  loadRepository = lib.optionalString runtimeRepository ''
    source ${./borg-repository} ${lib.escapeShellArg cfg.repositoryFile}
  '';
  passCommand = "${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.passphraseFile}";
  borgEnvironment = {
    # This deployment has no routed IPv6. Avoid an IPv6-first connection failure
    # while retaining the DNS name and strict host-key verification.
    BORG_RSH = "${pkgs.openssh}/bin/ssh -o AddressFamily=inet -i ${cfg.sshKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${cfg.knownHostsFile}";
    BORG_CONFIG_DIR = "/persist/borg/config";
    BORG_CACHE_DIR = "/persist/borg/cache";
  };
  cleanupScript = pkgs.writeShellScript "backup-cleanup" ''
    set -euo pipefail
    owner=/run/homelab-backup/owner
    # A failed lock acquisition must not recover a different operation's services.
    test -s "$owner" || exit 0
    test "$(cat "$owner")" = "''${INVOCATION_ID:?systemd invocation required}" || exit 0
    # A target stop is an intentional shutdown, not a backup failure. Do not
    # resurrect applications or network identity; retain recovery intent instead.
    systemctl is-active --quiet homelab-operational.target || exit 1
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
    repositoryFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/.+");
      default = null;
      description = "Private runtime file containing one remote ssh:// repository URI; mutually exclusive with repository.";
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
      default = "/persist/secrets/borg-passphrase";
    };
    sshKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/persist/secrets/borg-ssh-key";
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
        assertion = (cfg.repository != "") != runtimeRepository;
        message = "Set exactly one of repository or repositoryFile";
      }
    ];
    services.borgbackup.jobs.${cfg.name} = {
      repo = cfg.repository;
      wrapper = if runtimeRepository then null else "borg-job-${cfg.name}";
      paths = cfg.paths;
      exclude = cfg.excludes;
      doInit = false;
      failOnWarnings = true;
      encryption = {
        mode = "repokey-blake2";
        inherit passCommand;
      };
      environment = borgEnvironment;
      extraArgs = [ "--remote-path=${cfg.remotePath}" ];
      startAt = cfg.schedule;
      prune.keep = cfg.retention;
      readWritePaths = cfg.writablePaths ++ [ "/run/homelab-backup" ];
      preHook = ''
        ${loadRepository}
        exec 8>/run/homelab-backup/operation.lock
        ${pkgs.util-linux}/bin/flock -n 8
        systemctl is-active --quiet homelab-operational.target
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
    # The upstream wrapper embeds repo. For runtime endpoints use the same loader
    # as the native job, without sourcing operator-controlled shell code.
    environment.systemPackages = lib.optional runtimeRepository (
      pkgs.writeShellScriptBin "borg-job-${cfg.name}" ''
        set -euo pipefail
        ${loadRepository}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") borgEnvironment
        )}
        export BORG_PASSCOMMAND=${lib.escapeShellArg passCommand}
        exec ${pkgs.borgbackup}/bin/borg ${lib.escapeShellArgs [ "--remote-path=${cfg.remotePath}" ]} "$@"
      ''
    );
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
