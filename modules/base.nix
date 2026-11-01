{ pkgs, ... }: {
  environment.etc."homelab-contract.json".text = builtins.toJSON (import ../provision/containers.nix);
  system.stateVersion = "26.05";
  time.timeZone = "UTC";
  services.openssh.enable = false;
  services.resolved.settings.Resolve = {
    LLMNR = false;
    MulticastDNS = false;
  };
  users.mutableUsers = false;
  users.allowNoPasswordLogin = true; # root remains locked; recovery is pct enter
  users.users.root.hashedPassword = "!";
  # Recovery uses the authenticated Proxmox root console: pct enter ID.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
  environment.systemPackages = with pkgs; [
    age
    curl
    jq
    util-linux
    borgbackup
    ffmpeg
    libva-utils
    (writeShellScriptBin "verify-storage" (builtins.readFile ../scripts/verify-storage))
    (writeShellScriptBin "health-check" (builtins.readFile ../scripts/health-check))
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
