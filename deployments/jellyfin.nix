{ config, ... }:
let
  c = import ./jellyfin-contract.nix;
in
{
  imports = [
    ../modules/base.nix
    ../modules/proxmox-lxc.nix
    ../modules/persistence.nix
    ../modules/secrets.nix
    ../modules/lifecycle.nix
    ../modules/tailscale.nix
    ../modules/intel-media.nix
    ../modules/borgbackup.nix
    ../services/jellyfin
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
          path = c.media.path;
          marker = c.media.marker;
        }
      ];
      directories = [
        "/persist/secrets"
        "/persist/tailscale"
        "/persist/backup"
        "/persist/borg"
        "/persist/borg/config"
        "/persist/borg/cache"
      ];
    };
    secrets.requiredFiles = [
      config.homelab.backup.passphraseFile
      config.homelab.backup.sshKeyFile
    ];
    tailscale.serveTarget = "http://127.0.0.1:${toString c.application.port}";
    lifecycle.units = [
      "tailscaled"
      "tailscale-policy"
      "jellyfin-directories"
      "jellyfin"
    ];
    lifecycle.backupJob = "borgbackup-job-${config.homelab.backup.name}";
    intelMedia.renderGid = c.renderGid;
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
        "jellyfin"
      ];
      url = "http://127.0.0.1:${toString c.application.port}/health";
    };
  };
}
