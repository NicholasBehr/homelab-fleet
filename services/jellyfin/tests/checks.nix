{
  pkgs,
  jellyfin,
}:
let
  backupFixture =
    (jellyfin.extendModules {
      modules = [
        {
          homelab.backup = {
            enable = true;
            repository = "/tmp/disposable-test-repository";
            repositoryFile = pkgs.lib.mkForce null;
          };
        }
      ];
    }).config;
  importScript = jellyfin.config.systemd.services.rclone-import.serviceConfig.ExecStart;
  directoriesScript = pkgs.writeText "jellyfin-directories-script" (
    jellyfin.config.systemd.services.jellyfin-directories.script
  );
  jellyfinUnit = jellyfin.config.systemd.units."jellyfin.service".unit;
  importTimerUnit = jellyfin.config.systemd.units."rclone-import.timer".unit;
  networkTemplate = jellyfin.config.environment.etc."jellyfin/network-template.xml".source;
in
{
  service-config =
    assert jellyfin.config.services.jellyfin.enable;
    assert jellyfin.config.services.jellyfin.openFirewall == false;
    assert jellyfin.config.services.jellyfin.dataDir == "/persist/jellyfin";
    assert jellyfin.config.services.jellyfin.configDir == "/persist/jellyfin/config";
    assert jellyfin.config.services.jellyfin.cacheDir == "/persist/jellyfin/cache";
    assert jellyfin.config.services.jellyfin.hardwareAcceleration.enable;
    assert jellyfin.config.services.jellyfin.hardwareAcceleration.type == "qsv";
    assert jellyfin.config.services.jellyfin.hardwareAcceleration.device == "/dev/dri/renderD128";
    assert jellyfin.config.services.jellyfin.transcoding.hardwareDecodingCodecs.av1;
    assert jellyfin.config.services.jellyfin.transcoding.hardwareEncodingCodecs.hevc;
    assert !jellyfin.config.services.jellyfin.transcoding.hardwareEncodingCodecs.av1;
    assert jellyfin.config.systemd.tmpfiles.settings.jellyfinDirs == { };
    assert jellyfin.config.homelab.backup.paths == [ "/persist" ];
    assert jellyfin.config.homelab.backup.writablePaths == [ "/persist" ];
    assert builtins.length jellyfin.config.homelab.storage.volumes == 2;
    assert builtins.any (
      volume: volume.path == "/data" && volume.marker == "homelab-jellyfin-media-v1"
    ) jellyfin.config.homelab.storage.volumes;
    assert builtins.elem "/persist/secrets/rclone.conf" (jellyfin.config.homelab.secrets.requiredFiles);
    assert builtins.elem "/persist/secrets/rclone_known_hosts" (
      jellyfin.config.homelab.secrets.requiredFiles
    );
    assert jellyfin.config.homelab.tailscale.serveTarget == "http://127.0.0.1:8096";
    pkgs.runCommand "jellyfin-service-config" { } ''
      grep -q '<string>127.0.0.1</string>' ${networkTemplate}
      grep -q '<EnableIPv6>false</EnableIPv6>' ${networkTemplate}
      grep -q '/dev/dri/renderD128 rw' ${jellyfinUnit}
      grep -q '0750' ${directoriesScript}
      grep -q 'ensure_directory .*data/media/movies.*root jellyfin 0750' ${directoriesScript}
      grep -q 'rclone copy' ${importScript}
      grep -q -- '--compare-dest.*data/media/movies' ${importScript}
      grep -q -- '--compare-dest.*data/media/tv' ${importScript}
      grep -q 'source:movies' ${importScript}
      grep -q 'source:tv' ${importScript}
      ! grep -Eq 'rclone (sync|move)|--delete|--remove-source-files' ${importScript}
      grep -q 'OnUnitInactiveSec=5m' ${importTimerUnit}
      test ! -e ${
        jellyfin.config.environment.etc."systemd/system".source
      }/multi-user.target.wants/rclone-import.timer
      touch "$out"
    '';
  backup-config = backupFixture.system.build.toplevel;
  system = jellyfin.config.system.build.toplevel;
}
