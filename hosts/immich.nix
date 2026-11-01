{ ... }: {
  imports = [
    ../modules/base.nix
    ../modules/proxmox-lxc.nix
    ../modules/persistence.nix
    ../modules/secrets.nix
    ../modules/tailscale.nix
    ../modules/intel-media.nix
    ../modules/borgbackup.nix
    ../roles/immich.nix
  ];
}
