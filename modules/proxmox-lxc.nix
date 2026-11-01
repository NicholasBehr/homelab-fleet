{ modulesPath, ... }: {
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
    manageHostName = true;
  };
  networking.hostName = (import ../provision/containers.nix).hostname;
}
