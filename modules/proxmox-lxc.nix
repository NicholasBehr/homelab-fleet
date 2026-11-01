{ modulesPath, ... }: {
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
    manageHostName = true;
  };
  networking.hostName = (import ../provision/containers.nix).hostname;
  # 00-nixos.conf sorts before systemd's static-nodes-permissions.conf.
  # Keep the Proxmox-provided TUN node private to root (tailscaled).
  systemd.tmpfiles.rules = [ "z /dev/net/tun 0600 root root -" ];
}
