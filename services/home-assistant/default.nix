{
  config,
  lib,
  pkgs,
  ...
}:
let
  c = config.homelab.deployment.application;
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
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "zigbee2mqtt-enroll";
          runtimeInputs = [ pkgs.util-linux ];
          text = ''
            ${pkgs.bash}/bin/bash ${../../scripts/verify-storage} \
              ${lib.escapeShellArg config.homelab.deployment.persist.path} \
              ${lib.escapeShellArg config.homelab.deployment.persist.marker}
            exec ${pkgs.python3}/bin/python3 ${./enroll-zigbee2mqtt.py}
          '';
        })
      ];
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
            network_key = "!secret.yaml network_key";
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
        operational-ready.postStart = ''
          ${pkgs.python3}/bin/python3 ${./verify-zigbee-runtime.py} \
            ${lib.escapeShellArg c.zigbee2mqttSettingsFile} \
            ${lib.escapeShellArg c.zigbee2mqttSecretFile} \
            ${lib.escapeShellArg "${c.state}/.storage/core.config_entries"}
        '';
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
            secret_link=${lib.escapeShellArg "${c.zigbee2mqttState}/secret.yaml"}
            credential=/run/credentials/zigbee2mqtt.service/network.yaml
            if test -L "$secret_link"; then
              test "$(readlink "$secret_link")" = "$credential" || {
                echo 'Refusing unexpected Zigbee2MQTT secret link' >&2
                exit 1
              }
            elif test -e "$secret_link"; then
              echo 'Refusing non-symlink Zigbee2MQTT secret path' >&2
              exit 1
            else
              ln -s "$credential" "$secret_link"
            fi
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
            LoadCredential = [ "network.yaml:${c.zigbee2mqttSecretFile}" ];
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
