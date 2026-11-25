{
  config,
  lib,
  pkgs,
  ...
}:
let
  c = config.homelab.deployment;
  a = c.application;
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
  networkXml = pkgs.writeText "jellyfin-network.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration>
      <InternalHttpPort>${toString a.port}</InternalHttpPort>
      <InternalHttpsPort>8920</InternalHttpsPort>
      <PublicHttpPort>${toString a.port}</PublicHttpPort>
      <PublicHttpsPort>8920</PublicHttpsPort>
      <EnableHttps>false</EnableHttps>
      <RequireHttps>false</RequireHttps>
      <AutoDiscovery>false</AutoDiscovery>
      <EnableUPnP>false</EnableUPnP>
      <EnableIPv4>true</EnableIPv4>
      <EnableIPv6>false</EnableIPv6>
      <LocalNetworkAddresses>
        <string>127.0.0.1</string>
      </LocalNetworkAddresses>
    </NetworkConfiguration>
  '';
  importScript = pkgs.writeShellScript "jellyfin-rclone-import" ''
    set -euo pipefail
    exec 9>/run/jellyfin-import/lock
    ${pkgs.util-linux}/bin/flock -n 9 || {
      echo 'Another Jellyfin rclone import is still running' >&2
      exit 1
    }

    ${pkgs.python3}/bin/python ${./validate-rclone-config.py} \
      ${lib.escapeShellArg a.rcloneConfigFile} \
      ${lib.escapeShellArg a.rcloneRemote} \
      ${lib.escapeShellArg a.rcloneKnownHostsFile} \
      /persist/secrets

    ${pkgs.rclone}/bin/rclone copy \
      ${lib.escapeShellArg "${a.rcloneRemote}:${a.remoteMovies}"} \
      ${lib.escapeShellArg a.stagingMovies} \
      --config ${lib.escapeShellArg a.rcloneConfigFile} \
      --compare-dest ${lib.escapeShellArg a.movies} \
      --log-level INFO
    ${pkgs.rclone}/bin/rclone copy \
      ${lib.escapeShellArg "${a.rcloneRemote}:${a.remoteTv}"} \
      ${lib.escapeShellArg a.stagingTv} \
      --config ${lib.escapeShellArg a.rcloneConfigFile} \
      --compare-dest ${lib.escapeShellArg a.tv} \
      --log-level INFO

    ${pkgs.rclone}/bin/rclone lsjson \
      ${lib.escapeShellArg "${a.rcloneRemote}:${a.remoteMovies}"} \
      --config ${lib.escapeShellArg a.rcloneConfigFile} \
      --recursive --files-only | \
      ${pkgs.python3}/bin/python ${./promote.py} \
        ${lib.escapeShellArg a.stagingMovies} ${lib.escapeShellArg a.movies}
    ${pkgs.rclone}/bin/rclone lsjson \
      ${lib.escapeShellArg "${a.rcloneRemote}:${a.remoteTv}"} \
      --config ${lib.escapeShellArg a.rcloneConfigFile} \
      --recursive --files-only | \
      ${pkgs.python3}/bin/python ${./promote.py} \
        ${lib.escapeShellArg a.stagingTv} ${lib.escapeShellArg a.tv}
  '';
in
{
  config = lib.mkMerge [
    {
      environment.etc."homelab-versions.json".text = builtins.toJSON {
        caddy = pkgs.caddy.version;
        jellyfin = config.services.jellyfin.package.version;
        rclone = pkgs.rclone.version;
        contractVersion = c.contractVersion;
      };
      environment.etc."jellyfin/network-template.xml".source = networkXml;
      homelab.backup = {
        paths = [ "/persist" ];
        writablePaths = [ "/persist" ];
        excludes = [ "/persist/borg/cache" ];
        prepare = "${pkgs.bash}/bin/bash ${./backup-prepare}";
        cleanup = "${pkgs.bash}/bin/bash ${./backup-cleanup}";
      };
      services.jellyfin = {
        enable = true;
        openFirewall = false;
        dataDir = a.state;
        configDir = "${a.state}/config";
        logDir = "${a.state}/logs";
        cacheDir = "${a.state}/cache";
        hardwareAcceleration = {
          enable = true;
          type = "qsv";
          device = c.renderDevice;
        };
        transcoding = {
          enableHardwareEncoding = true;
          hardwareDecodingCodecs = {
            av1 = true;
            h264 = true;
            hevc = true;
            hevc10bit = true;
            vp9 = true;
          };
          hardwareEncodingCodecs.hevc = true;
        };
      };
      users.users.jellyfin = {
        uid = lib.mkForce a.uid;
        extraGroups = [ "render" ];
      };
      users.groups.jellyfin.gid = lib.mkForce a.gid;
      environment.systemPackages = [
        pkgs.rclone
        pkgs.libva-utils
      ];
      systemd.tmpfiles.settings.jellyfinDirs = lib.mkForce { };
      systemd.services = {
        operational-ready.script = lib.mkAfter ''
          ${pkgs.python3}/bin/python3 ${../../scripts/verify-secret} ${
            lib.escapeShellArgs [
              config.homelab.backup.repositoryFile
              config.homelab.backup.knownHostsFile
            ]
          }
        '';
        rclone-ready = {
          requires = [ "operational-ready.service" ];
          after = [ "operational-ready.service" ];
          partOf = [ "homelab-operational.target" ];
          unitConfig.ConditionPathExists = [
            a.rcloneConfigFile
            a.rcloneKnownHostsFile
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.python3}/bin/python3 ${../../scripts/verify-secret} ${
              lib.escapeShellArgs [
                a.rcloneConfigFile
                a.rcloneKnownHostsFile
              ]
            }
          '';
        };
        jellyfin-directories = {
          inherit (gate) requires after;
          path = [ pkgs.glibc.getent ];
          before = [
            "jellyfin.service"
            "rclone-import.service"
          ];
          requiredBy = [
            "jellyfin.service"
            "rclone-import.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ensure_directory() {
              path=$1 owner=$2 group=$3 mode=$4
              if test -L "$path" || { test -e "$path" && ! test -d "$path"; }; then
                echo "Refusing unsafe Jellyfin directory: $path" >&2
                exit 1
              fi
              if test -e "$path"; then
                mode=''${mode#0}
                expected="$(id -u "$owner"):$(getent group "$group" | cut -d: -f3):$mode"
                actual="$(stat -c '%u:%g:%a' "$path")"
                test "$actual" = "$expected" || {
                  echo "Unexpected Jellyfin directory ownership or mode: $path" >&2
                  exit 1
                }
              else
                install -d -m "$mode" -o "$owner" -g "$group" -- "$path"
              fi
            }
            ensure_directory ${lib.escapeShellArg a.state} jellyfin jellyfin 0700
            ensure_directory ${lib.escapeShellArg "${a.state}/config"} jellyfin jellyfin 0700
            ensure_directory ${lib.escapeShellArg "${a.state}/logs"} jellyfin jellyfin 0700
            ensure_directory ${lib.escapeShellArg "${a.state}/cache"} jellyfin jellyfin 0700
            ensure_directory ${lib.escapeShellArg "${a.state}/transcodes"} jellyfin jellyfin 0700
            ensure_directory /data/media root jellyfin 0750
            ensure_directory ${lib.escapeShellArg a.movies} root jellyfin 0750
            ensure_directory ${lib.escapeShellArg a.tv} root jellyfin 0750
            ensure_directory /data/staging root jellyfin 0750
            ensure_directory ${lib.escapeShellArg a.stagingMovies} root jellyfin 0750
            ensure_directory ${lib.escapeShellArg a.stagingTv} root jellyfin 0750
          '';
        };
        jellyfin = gate // {
          wantedBy = lib.mkForce [ ];
          serviceConfig.ReadWritePaths = [ a.state ];
          preStart = lib.mkAfter ''
            ${pkgs.python3}/bin/python ${./network-config.py} \
              ${lib.escapeShellArg "${a.state}/config/network.xml"} \
              ${networkXml} ${toString a.uid} ${toString a.gid} ${toString a.port}
          '';
        };
        rclone-import = gate // {
          requires = gate.requires ++ [ "rclone-ready.service" ];
          wantedBy = lib.mkForce [ ];
          partOf = [ "homelab-operational.target" ];
          unitConfig.ConditionPathExists = [
            a.rcloneConfigFile
            a.rcloneKnownHostsFile
          ];
          wants = [ "network-online.target" ];
          after = gate.after ++ [
            "rclone-ready.service"
            "network-online.target"
            "jellyfin.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "jellyfin";
            UMask = "0027";
            Environment = [ "HOME=/run/jellyfin-import" ];
            ExecStart = importScript;
            RuntimeDirectory = "jellyfin-import";
            RuntimeDirectoryMode = "0700";
            ReadWritePaths = [
              a.stagingMovies
              a.stagingTv
              a.movies
              a.tv
              "/run/jellyfin-import"
            ];
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            CapabilityBoundingSet = [ "" ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
            LockPersonality = true;
          };
        };
      };
      systemd.timers.rclone-import = {
        unitConfig.ConditionPathExists = [
          a.rcloneConfigFile
          a.rcloneKnownHostsFile
        ];
        wantedBy = [ "homelab-operational.target" ];
        partOf = [ "homelab-operational.target" ];
        requires = [
          "operational-ready.service"
          "rclone-ready.service"
        ];
        after = [
          "operational-ready.service"
          "rclone-ready.service"
          "jellyfin.service"
        ];
        timerConfig = {
          OnUnitInactiveSec = "5m";
          Unit = "rclone-import.service";
        };
      };
      systemd.targets.homelab-operational.wants = [ "rclone-import.timer" ];
    }
  ];
}
