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
    secrets.encryptedFile =
      if builtins.pathExists ../secrets/immich.yaml then ../secrets/immich.yaml else null;
    tailscale.serveTarget =
      if config.homelab.image.variant == "bootstrap" then null else "http://127.0.0.1:2283";
    intelMedia.renderGid = c.renderGid;
    backup = {
      enable = config.homelab.image.variant == "operational";
      repositoryFile = "/persist/borg/repository";
      schedule = "*-*-* 02:15:00 Europe/Zurich";
    };
    health = {
      units = [
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
