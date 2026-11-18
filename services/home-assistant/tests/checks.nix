{
  pkgs,
  home-assistant,
}:
let
  backupFixture =
    (home-assistant.extendModules {
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
in
{
  backup-config = backupFixture.system.build.toplevel;
  service-config =
    assert home-assistant.config.services.home-assistant.configDir == "/persist/home-assistant";
    assert home-assistant.config.services.home-assistant.openFirewall == false;
    assert home-assistant.config.services.home-assistant.openFirewallForComponents == false;
    assert
      home-assistant.config.services.home-assistant.extraComponents == [
        "mobile_app"
        "mqtt"
        "smlight"
      ];
    assert home-assistant.config.services.home-assistant.config.mobile_app == { };
    assert home-assistant.config.services.mosquitto.enable;
    assert home-assistant.config.services.mosquitto.dataDir == "/persist/mosquitto";
    assert
      home-assistant.config.services.mosquitto.listeners == [
        {
          address = "127.0.0.1";
          port = 1883;
          omitPasswordAuth = true;
          acl = [ "topic readwrite #" ];
          authPlugins = [ ];
          users = { };
          settings.allow_anonymous = true;
        }
      ];
    assert home-assistant.config.services.zigbee2mqtt.enable;
    assert home-assistant.config.services.zigbee2mqtt.dataDir == "/persist/zigbee2mqtt";
    assert home-assistant.config.services.zigbee2mqtt.settings.serial.adapter == "zstack";
    assert
      home-assistant.config.services.zigbee2mqtt.settings.serial.port == "tcp://runtime.invalid:7638";
    assert builtins.elem "/persist/secrets/zigbee2mqtt.env" (
      home-assistant.config.homelab.secrets.requiredFiles
    );
    assert home-assistant.config.services.zigbee2mqtt.settings.homeassistant.enabled;
    assert home-assistant.config.services.zigbee2mqtt.settings.permit_join == false;
    assert home-assistant.config.services.zigbee2mqtt.settings.advanced.network_key == "GENERATE";
    assert home-assistant.config.services.zigbee2mqtt.settings.advanced.pan_id == "GENERATE";
    assert home-assistant.config.services.zigbee2mqtt.settings.advanced.ext_pan_id == "GENERATE";
    assert home-assistant.config.services.zigbee2mqtt.settings.frontend.base_url == "/zigbee2mqtt";
    assert
      home-assistant.config.homelab.tailscale.serveRoutes."/zigbee2mqtt"
      == "http://127.0.0.1:8080/zigbee2mqtt/";
    assert home-assistant.config.homelab.health.url == "http://127.0.0.1:8123/manifest.json";
    assert home-assistant.config.homelab.health.httpStatus == 200;
    pkgs.runCommand "home-assistant-service-config" { } ''
      grep -q 'Requires=.*operational-ready.service' \
        ${home-assistant.config.systemd.units."home-assistant.service".unit}/home-assistant.service
      grep -q 'Wants=.*zigbee2mqtt.service' \
        ${home-assistant.config.systemd.units."home-assistant.service".unit}/home-assistant.service
      ! grep -q 'Requires=.*zigbee2mqtt.service' \
        ${home-assistant.config.systemd.units."home-assistant.service".unit}/home-assistant.service
      grep -q 'Requires=.*mosquitto.service' \
        ${home-assistant.config.systemd.units."zigbee2mqtt.service".unit}/zigbee2mqtt.service
      grep -q 'EnvironmentFile=/persist/secrets/zigbee2mqtt.env' \
        ${home-assistant.config.systemd.units."zigbee2mqtt.service".unit}/zigbee2mqtt.service
      grep -q 'zigbee2mqtt-config-init' \
        ${home-assistant.config.systemd.units."zigbee2mqtt.service".unit}/zigbee2mqtt.service
      grep -q '127.0.0.1' \
        ${pkgs.writeText "home-assistant-config" (
          builtins.toJSON home-assistant.config.services.home-assistant.config
        )}
      grep -q 'home-assistant' \
        ${pkgs.writeText "home-assistant-versions"
          home-assistant.config.environment.etc."homelab-versions.json".text
        }
      grep -q 'zigbee2mqtt' \
        ${pkgs.writeText "home-assistant-versions-zigbee2mqtt"
          home-assistant.config.environment.etc."homelab-versions.json".text
        }
      touch "$out"
    '';
  system = home-assistant.config.system.build.toplevel;
}
