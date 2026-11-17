{
  config,
  lib,
  pkgs,
  ...
}:
let
  c = config.homelab.deployment.application;
  zigbee2mqttConfig = (pkgs.formats.yaml { }).generate "zigbee2mqtt.yaml" (
    config.services.zigbee2mqtt.settings
  );
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
  config = lib.mkMerge [
    {
      environment.etc."homelab-versions.json".text = builtins.toJSON {
        "home-assistant" = config.services.home-assistant.finalPackage.version;
        mosquitto = config.services.mosquitto.package.version;
        zigbee2mqtt = config.services.zigbee2mqtt.package.version;
        contractVersion = config.homelab.deployment.contractVersion;
      };
    }
    {
      homelab.backup = {
        paths = [ "/persist" ];
        writablePaths = [ "/persist" ];
        excludes = [
          "/persist/borg/cache"
          "/persist/home-assistant/backups/*.tmp"
        ];
        prepare = "${pkgs.bash}/bin/bash ${./backup-prepare}";
        cleanup = "${pkgs.bash}/bin/bash ${./backup-cleanup}";
      };
      services.home-assistant = {
        enable = true;
        configDir = c.state;
        openFirewall = false;
        openFirewallForComponents = false;
        extraComponents = lib.mkForce [
          "mobile_app"
          "mqtt"
          "smlight"
        ];
        config = {
          mobile_app = { };
          http = {
            server_host = "127.0.0.1";
            server_port = c.port;
            use_x_forwarded_for = true;
            trusted_proxies = [
              "127.0.0.1"
              "::1"
            ];
            ip_ban_enabled = true;
            login_attempts_threshold = 5;
          };
        };
      };
      users.users.hass = {
        uid = lib.mkForce c.uid;
        createHome = lib.mkForce false;
        isSystemUser = true;
      };
      users.groups.hass.gid = lib.mkForce c.gid;
      services.mosquitto = {
        enable = true;
        dataDir = c.mosquittoState;
        listeners = [
          {
            address = "127.0.0.1";
            port = c.mosquittoPort;
            omitPasswordAuth = true;
            acl = [ "topic readwrite #" ];
            settings.allow_anonymous = true;
          }
        ];
      };
      services.zigbee2mqtt = {
        enable = true;
        dataDir = c.zigbee2mqttState;
        settings = {
          version = 5;
          homeassistant.enabled = true;
          permit_join = false;
          mqtt = {
            base_topic = "zigbee2mqtt";
            server = "mqtt://127.0.0.1:${toString c.mosquittoPort}";
          };
          serial = {
            # The private operator file overrides this non-routable sentinel.
            port = "tcp://runtime.invalid:7638";
            adapter = "zstack";
            baudrate = 115200;
            rtscts = false;
          };
          advanced = {
            channel = 15;
            network_key = "GENERATE";
            pan_id = "GENERATE";
            ext_pan_id = "GENERATE";
          };
          frontend = {
            enabled = true;
            host = "127.0.0.1";
            port = c.zigbee2mqttFrontendPort;
            base_url = "/zigbee2mqtt";
          };
        };
      };
      users.users.zigbee2mqtt = {
        uid = lib.mkForce c.zigbee2mqttUid;
        createHome = lib.mkForce false;
        isSystemUser = true;
      };
      users.groups.zigbee2mqtt.gid = lib.mkForce c.zigbee2mqttGid;
      users.users.mosquitto = {
        uid = lib.mkForce c.mosquittoUid;
        createHome = lib.mkForce false;
        isSystemUser = true;
      };
      users.groups.mosquitto.gid = lib.mkForce c.mosquittoGid;
      # The upstream target also starts the service at boot. Keep the entire
      # workload behind the explicit operational activation boundary.
      systemd.targets.home-assistant.wantedBy = lib.mkForce [ ];
      systemd.services = {
        home-assistant-directories = {
          inherit (gate) requires after;
          before = [
            "home-assistant.service"
            "mosquitto.service"
            "zigbee2mqtt.service"
          ];
          requiredBy = [
            "home-assistant.service"
            "mosquitto.service"
            "zigbee2mqtt.service"
          ];
          serviceConfig.Type = "oneshot";
          script = ''
            install -d -m 0700 -o hass -g hass ${lib.escapeShellArg c.state}
            install -d -m 0700 -o hass -g hass ${lib.escapeShellArg "${c.state}/backups"}
            install -d -m 0700 -o zigbee2mqtt -g zigbee2mqtt ${lib.escapeShellArg c.zigbee2mqttState}
            install -d -m 0700 -o mosquitto -g mosquitto ${lib.escapeShellArg c.mosquittoState}
          '';
        };
        mosquitto = gate;
        zigbee2mqtt = gate // {
          wants = [ "network-online.target" ];
          requires = [ "mosquitto.service" ] ++ gate.requires;
          after = [
            "mosquitto.service"
            "network-online.target"
          ]
          ++ gate.after;
          serviceConfig = {
            EnvironmentFile = c.zigbee2mqttSettingsFile;
            # NixOS normally replaces configuration.yaml from the Nix store on
            # every start. Zigbee2MQTT writes generated network identity there;
            # preserve it after first start and let upstream migrations run.
            # Remove when upstream supports preserving mutable generated config.
            ExecStartPre = lib.mkForce [
              "${pkgs.writeShellScript "zigbee2mqtt-config-init" ''
                config=${lib.escapeShellArg "${c.zigbee2mqttState}/configuration.yaml"}
                test ! -L "$config" || { echo 'Refusing symlinked Zigbee2MQTT configuration' >&2; exit 1; }
                test ! -e "$config" || test -f "$config" || {
                  echo 'Refusing non-file Zigbee2MQTT configuration path' >&2
                  exit 1
                }
                if test ! -e "$config"; then
                  ${pkgs.coreutils}/bin/cp --no-preserve=mode ${zigbee2mqttConfig} "$config"
                fi
              ''}"
            ];
          };
        };
        home-assistant = gate // {
          wants = [ "network-online.target" ];
          requires = [ "zigbee2mqtt.service" ] ++ gate.requires;
          after = [
            "network-online.target"
            "zigbee2mqtt.service"
          ]
          ++ gate.after;
        };
      };
    }
  ];
}
