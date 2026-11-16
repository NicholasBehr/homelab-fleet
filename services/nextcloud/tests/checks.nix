{
  pkgs,
  nextcloud,
}:
let
  c = nextcloud.config;
in
{
  system = c.system.build.toplevel;
  restore = import ./restore.nix { inherit pkgs; };
  service-config =
    assert c.services.nextcloud.settings.datadirectory == "/data/nextcloud";
    assert c.services.nextcloud.datadir == "/persist/nextcloud";
    assert c.services.nextcloud.config.adminpassFile == null;
    assert c.services.nextcloud.appstoreEnable == false;
    assert c.services.nextcloud.autoUpdateApps.enable == false;
    assert c.services.nextcloud.settings.shareapi_allow_links == false;
    assert c.services.nextcloud.config.dbpassFile == null;
    assert c.services.postgresql.enableTCPIP == false;
    assert c.services.nextcloud.phpOptions.memory_limit == "512M";
    assert c.services.nextcloud.maxUploadSize == "10G";
    assert c.systemd.services.nextcloud-install.wantedBy == [ ];
    assert c.systemd.services.nextcloud-install.environment.NC_setup_create_db_user == "false";
    assert
      c.systemd.services.nextcloud-install.serviceConfig.LoadCredential
      == [ "secret_file:/persist/secrets/nextcloud-settings.json" ];
    assert
      c.services.nginx.virtualHosts.localhost.listen == [
        {
          addr = "127.0.0.1";
          port = 8080;
          ssl = false;
          extraParameters = [ ];
          proxyProtocol = false;
        }
      ];
    assert !(builtins.any (rule: pkgs.lib.hasInfix "/persist/nextcloud" rule) c.systemd.tmpfiles.rules);
    assert c.systemd.services.nextcloud-cron.serviceConfig.KillMode == "control-group";
    assert c.systemd.services.nextcloud-setup.wants == [ ];
    pkgs.runCommand "nextcloud-service-config" { } ''
      grep -q 'ConditionPathExists=/var/lib/homelab/operational-enabled' \
        ${c.systemd.units."phpfpm-nextcloud.service".unit}/phpfpm-nextcloud.service
      grep -q 'Refusing symlinked state' ${pkgs.writeText "directories" c.systemd.services.nextcloud-directories.script}
      if grep -E 'maintenance:install|DBPASS|ADMINPASS|rm -r' ${pkgs.writeText "setup" c.systemd.services.nextcloud-setup.script}; then exit 1; fi
      touch "$out"
    '';
}
