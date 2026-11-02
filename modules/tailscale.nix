{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.homelab.tailscale.serveTarget = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
  };
  config = {
    services.tailscale = {
      enable = true;
      openFirewall = false;
      extraDaemonFlags = [
        "--state=/persist/tailscale/tailscaled.state"
        "--statedir=/persist/tailscale"
      ];
    };
    systemd.services.tailscale-policy = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "tailscaled.service" ];
      after = [ "tailscaled.service" ];
      path = [
        pkgs.tailscale
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = 15;
      };
      script = ''
        test "$(tailscale status --json | jq -r .BackendState)" = Running
        tailscale set --ssh=true --accept-routes=false
        # Own the complete Serve configuration, removing obsolete forwards.
        tailscale serve reset
        ${lib.optionalString (
          config.homelab.tailscale.serveTarget != null
        ) "tailscale serve --bg --https=443 ${lib.escapeShellArg config.homelab.tailscale.serveTarget}"}
      '';
    };
  };
}
