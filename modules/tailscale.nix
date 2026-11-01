{
  pkgs,
  bootstrap,
  lib,
  ...
}:
{
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
      ${lib.optionalString (!bootstrap) "tailscale serve --bg --https=443 http://127.0.0.1:2283"}
    '';
  };
}
