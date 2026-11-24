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
  rcloneReadyScript = pkgs.writeText "jellyfin-rclone-ready-script" (
    jellyfin.config.systemd.services.rclone-ready.script
  );
  operationalReadyScript = pkgs.writeText "jellyfin-operational-ready-script" (
    jellyfin.config.systemd.services.operational-ready.script
  );
  jellyfinUnit = jellyfin.config.systemd.units."jellyfin.service".unit;
  importTimerUnit = jellyfin.config.systemd.units."rclone-import.timer".unit;
  networkTemplate = jellyfin.config.environment.etc."jellyfin/network-template.xml".source;
in
{
  service-config =
    assert jellyfin.config.services.jellyfin.enable;
    assert jellyfin.config.homelab.deployment.cores == 4;
    assert jellyfin.config.homelab.deployment.memoryMiB == 8192;
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
    assert builtins.elem "/persist/borg" jellyfin.config.homelab.storage.directories;
    assert builtins.any (
      volume: volume.path == "/data" && volume.marker == "homelab-jellyfin-media-v1"
    ) jellyfin.config.homelab.storage.volumes;
    assert !builtins.elem "/persist/secrets/rclone.conf" jellyfin.config.homelab.secrets.requiredFiles;
    assert
      !builtins.elem "/persist/secrets/rclone_known_hosts" jellyfin.config.homelab.secrets.requiredFiles;
    assert builtins.elem jellyfin.config.homelab.backup.passphraseFile (
      jellyfin.config.homelab.secrets.requiredFiles
    );
    assert builtins.elem jellyfin.config.homelab.backup.sshKeyFile (
      jellyfin.config.homelab.secrets.requiredFiles
    );
    assert jellyfin.config.homelab.tailscale.serveTarget == "http://127.0.0.1:8096";
    assert !builtins.elem "rclone-import.timer" jellyfin.config.homelab.health.units;
    assert builtins.elem "rclone-ready.service" jellyfin.config.systemd.services.rclone-import.requires;
    assert builtins.elem "rclone-ready.service" jellyfin.config.systemd.timers.rclone-import.requires;
    assert !builtins.elem "rclone-ready.service" jellyfin.config.systemd.services.jellyfin.requires;
    assert !builtins.elem "rclone-ready.service" jellyfin.config.systemd.services.tailscaled.requires;
    assert
      !builtins.elem "rclone-ready.service" (
        jellyfin.config.systemd.services."borgbackup-job-jellyfin".requires
      );
    pkgs.runCommand "jellyfin-service-config" { } ''
      grep -q '<string>127.0.0.1</string>' ${networkTemplate}
      grep -q '<EnableIPv6>false</EnableIPv6>' ${networkTemplate}
      grep -q '/dev/dri/renderD128 rw' ${jellyfinUnit}/jellyfin.service
      grep -q '0750' ${directoriesScript}
      grep -q 'ensure_directory .*data/media/movies.*root jellyfin 0750' ${directoriesScript}
      grep -q 'rclone copy' ${importScript}
      grep -q -- '--compare-dest.*data/media/movies' ${importScript}
      grep -q -- '--compare-dest.*data/media/tv' ${importScript}
      grep -q 'source:movies' ${importScript}
      grep -q 'source:tv' ${importScript}
      ! grep -Eq 'rclone (sync|move)|--delete|--remove-source-files' ${importScript}
      grep -q 'OnUnitInactiveSec=5m' ${importTimerUnit}/rclone-import.timer
      grep -q '/persist/secrets/rclone.conf' ${rcloneReadyScript}
      grep -q '/persist/secrets/rclone_known_hosts' ${rcloneReadyScript}
      ! grep -q '/persist/secrets/rclone' ${operationalReadyScript}
      grep -q '/persist/secrets/borg-passphrase' ${operationalReadyScript}
      grep -q '/persist/secrets/borg-ssh-key' ${operationalReadyScript}
      grep -q '/persist/borg/repository' ${operationalReadyScript}
      grep -q '/persist/borg/known_hosts' ${operationalReadyScript}
      test ! -e ${
        jellyfin.config.environment.etc."systemd/system".source
      }/multi-user.target.wants/rclone-import.timer
      touch "$out"
    '';
  backup-config = backupFixture.system.build.toplevel;
  system = jellyfin.config.system.build.toplevel;
}
