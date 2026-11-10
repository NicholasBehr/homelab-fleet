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
      ];
    };
    secrets.requiredFiles = [
      config.homelab.backup.passphraseFile
      config.homelab.backup.sshKeyFile
    ];
    tailscale.serveTarget = "http://127.0.0.1:8123";
    lifecycle.units = [
      "tailscaled"
      "tailscale-policy"
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
        "home-assistant"
      ];
      url = "http://127.0.0.1:8123/api/";
      httpStatus = 401; # API is reachable and correctly requires authentication.
    };
  };
}
