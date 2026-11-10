{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.homelab = {
    deployment = lib.mkOption {
      type = lib.types.attrs;
      description = "Operator deployment contract, exported in the release manifest.";
    };
    health.units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    health.backupMaxAgeSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 129600;
    };
    health.url = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    health.httpStatus = lib.mkOption {
      type = lib.types.ints.between 100 599;
      default = 200;
      description = "Expected status from the unauthenticated local HTTP readiness probe.";
    };
  };
  config = {
    environment.etc."homelab-contract.json".text = builtins.toJSON config.homelab.deployment;
    environment.etc."homelab-health.json".text = builtins.toJSON {
      inherit (config.homelab.health)
        units
        url
        httpStatus
        backupMaxAgeSeconds
        ;
      backupEnabled = config.homelab.backup.enable;
      backupName = config.homelab.backup.name;
    };
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
      curl
      jq
      util-linux
      borgbackup
      (writeShellScriptBin "verify-storage" (builtins.readFile ../scripts/verify-storage))
      (writeShellScriptBin "health-check" (builtins.readFile ../scripts/health-check))
    ];
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
}
