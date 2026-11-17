{ config, lib, ... }:
let
  c = import ./home-assistant-contract.nix;
in
{
  imports = [
    ../modules/base.nix
    ../modules/proxmox-lxc.nix
    ../modules/persistence.nix
    ../modules/secrets.nix
    ../modules/lifecycle.nix
    ../modules/tailscale.nix
    ../modules/borgbackup.nix
    ../services/home-assistant
  ];
  networking.hostName = c.hostname;
  homelab = {
    deployment = c;
    storage = {
      volumes = [
        {
          path = c.persist.path;
          marker = c.persist.marker;
        }
      ];
      directories = [
        "/persist/secrets"
        "/persist/tailscale"
        "/persist/backup"
        "/persist/borg/config"
        "/persist/borg/cache"
        "/persist/home-assistant/backups"
        c.application.zigbee2mqttState
        c.application.mosquittoState
      ];
    };
    secrets.requiredFiles = [
      config.homelab.backup.passphraseFile
      config.homelab.backup.sshKeyFile
      c.application.zigbee2mqttSettingsFile
      c.application.zigbee2mqttSecretFile
    ];
    tailscale.serveTarget = "http://127.0.0.1:8123";
    tailscale.serveRoutes."/zigbee2mqtt" =
      "http://127.0.0.1:${toString c.application.zigbee2mqttFrontendPort}";
    lifecycle.units = [
      "tailscaled"
      "tailscale-policy"
      "mosquitto"
      "zigbee2mqtt"
      "home-assistant"
      "home-assistant-directories"
    ];
    lifecycle.backupJob = "borgbackup-job-${config.homelab.backup.name}";
    backup = {
      enable = true;
      repositoryFile = "/persist/borg/repository";
      schedule = "*-*-* 01:30:00 Europe/Zurich";
    };
    health = {
      units = [
        "homelab-operational.target"
        "storage-contract"
        "operational-ready"
        "tailscaled"
        "mosquitto"
        "zigbee2mqtt"
        "home-assistant"
      ];
      # An unauthenticated API request counts as a failed login and can ban
      # loopback; the frontend root is a non-authenticating readiness probe.
      url = "http://127.0.0.1:8123/";
      httpStatus = 200;
    };
  };
}
