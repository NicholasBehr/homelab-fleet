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
    secrets.encryptedFile =
      if builtins.pathExists ../secrets/home-assistant.yaml then ../secrets/home-assistant.yaml else null;
    tailscale.serveTarget =
      if config.homelab.image.variant == "bootstrap" then null else "http://127.0.0.1:8123";
    backup = {
      enable = config.homelab.image.variant == "operational";
      repositoryFile = "/persist/borg/repository";
      schedule = "*-*-* 01:30:00 Europe/Zurich";
    };
    health = {
      units = [
        "storage-contract"
        "operational-ready"
        "tailscaled"
        "home-assistant"
      ];
      url = "http://127.0.0.1:8123/api/";
    };
  };
}
