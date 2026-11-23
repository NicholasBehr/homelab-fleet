{ config, ... }:
let
  c = import ./paperless-ngx-contract.nix;
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
    ../services/paperless-ngx
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
      "paperless-directories"
      "paperless-secret-key"
      "postgresql"
      "redis-paperless"
      "paperless-scheduler"
      "paperless-task-queue"
      "paperless-consumer"
      "paperless-web"
    ];
    lifecycle.backupJob = "borgbackup-job-${config.homelab.backup.name}";
    backup = {
      enable = true;
      repositoryFile = "/persist/borg/repository";
      schedule = "*-*-* 02:30:00 Europe/Zurich";
    };
    health = {
      units = [
        "homelab-operational.target"
        "storage-contract"
        "operational-ready"
        "tailscaled"
        "postgresql"
        "redis-paperless"
        "paperless-scheduler"
        "paperless-task-queue"
        "paperless-consumer"
        "paperless-web"
      ];
      url = "http://localhost:${toString c.application.port}/";
      httpStatus = 200;
    };
  };
}
