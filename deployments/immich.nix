{ config, lib, ... }:
let
  c = import ./immich-contract.nix;
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
    ../services/immich
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
        "/persist/borg/config"
        "/persist/borg/cache"
      ];
    };
    secrets.requiredFiles = [
      config.homelab.backup.passphraseFile
      config.homelab.backup.sshKeyFile
    ];
    tailscale.serveTarget = "http://127.0.0.1:2283";
    lifecycle.units = [
      "tailscaled"
      "tailscale-policy"
      "immich-server"
      "immich-machine-learning"
      "postgresql"
      "postgresql-setup"
      "redis-immich"
      "immich-directories"
    ];
    lifecycle.backupJob = "borgbackup-job-${config.homelab.backup.name}";
    intelMedia.renderGid = c.renderGid;
    backup = {
      enable = true;
      repositoryFile = "/persist/borg/repository";
      schedule = "*-*-* 02:15:00 Europe/Zurich";
    };
    health = {
      units = [
        "homelab-operational.target"
        "storage-contract"
        "operational-ready"
        "tailscaled"
        "postgresql"
        "redis-immich"
        "immich-server"
        "immich-machine-learning"
      ];
      url = "http://127.0.0.1:2283/api/server/ping";
    };
  };
}
