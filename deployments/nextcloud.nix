{ config, ... }:
let
  c = import ./nextcloud-contract.nix;
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
    ../services/nextcloud
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
        {
          path = c.data.path;
          marker = c.data.marker;
        }
      ];
      directories = [
        "/persist/secrets"
        "/persist/tailscale"
        "/persist/backup"
        "/persist/borg/config"
        "/persist/borg/cache"
      ];
    };
    secrets.requiredFiles = [
      config.homelab.backup.passphraseFile
      config.homelab.backup.sshKeyFile
      c.application.settingsFile
    ];
    tailscale.serveTarget = "http://127.0.0.1:${toString c.application.port}";
    lifecycle.units = [
      "tailscaled"
      "tailscale-policy"
      "nextcloud-directories"
      "postgresql"
      "redis-nextcloud"
      "nextcloud-setup"
      "phpfpm-nextcloud"
      "nginx"
    ];
    lifecycle.backupJob = "borgbackup-job-${config.homelab.backup.name}";
    backup = {
      enable = true;
      repositoryFile = "/persist/borg/repository";
      schedule = "*-*-* 03:00:00 Europe/Zurich";
    };
    health = {
      units = [
        "homelab-operational.target"
        "storage-contract"
        "operational-ready"
        "tailscaled"
        "postgresql"
        "redis-nextcloud"
        "phpfpm-nextcloud"
        "nginx"
      ];
      url = "http://127.0.0.1:${toString c.application.port}/status.php";
    };
  };
}
