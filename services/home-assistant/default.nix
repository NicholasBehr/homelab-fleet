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
      environment.etc."homelab-versions.json".text = builtins.toJSON {
        "home-assistant" = config.services.home-assistant.finalPackage.version;
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
          "zha"
          "smlight"
        ];
        config = {
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
      # The upstream target also starts the service at boot. Keep the entire
      # workload behind the explicit operational activation boundary.
      systemd.targets.home-assistant.wantedBy = lib.mkForce [ ];
      systemd.services = {
        home-assistant-directories = {
          inherit (gate) requires after;
          before = [ "home-assistant.service" ];
          requiredBy = [ "home-assistant.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            install -d -m 0700 -o hass -g hass ${lib.escapeShellArg c.state}
            install -d -m 0700 -o hass -g hass ${lib.escapeShellArg "${c.state}/backups"}
          '';
        };
        home-assistant = gate // {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ] ++ gate.after;
        };
      };
    }
  ];
}
