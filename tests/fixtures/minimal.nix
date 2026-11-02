{ ... }: {
  imports = [
    ../../modules/base.nix
    ../../modules/proxmox-lxc.nix
    ../../modules/persistence.nix
    ../../modules/secrets.nix
    ../../modules/tailscale.nix
    ../../modules/borgbackup.nix
  ];
  networking.hostName = "module-fixture";
  homelab.deployment = {
    service = "module-fixture";
  };
  homelab.storage.volumes = [
    {
      path = "/persist";
      marker = "disposable-fixture";
    }
  ];
}
