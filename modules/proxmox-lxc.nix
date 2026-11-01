{
  config,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
    manageHostName = true;
  };
  networking.hostName = (import ../provision/containers.nix).hostname;
  # tmpfiles applies both matching z rules; an earlier rule does not override
  # the vendor rule. Replace only its TUN mode, preserving all other defaults.
  environment.etc."tmpfiles.d/static-nodes-permissions.conf".source =
    pkgs.runCommand "private-tun-static-node-permissions.conf" { }
      ''
        substitute ${config.systemd.package}/example/tmpfiles.d/static-nodes-permissions.conf "$out" \
          --replace-fail "z /dev/net/tun      0666" "z /dev/net/tun      0600"
      '';
}
