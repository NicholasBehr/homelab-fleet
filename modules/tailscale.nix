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
  options.homelab.tailscale.serveRoutes = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Additional tailnet-only HTTPS path proxies.";
  };
  config = {
    assertions = [
      {
        assertion = builtins.all (path: lib.hasPrefix "/" path) (
          builtins.attrNames config.homelab.tailscale.serveRoutes
        );
        message = "Tailscale Serve route paths must begin with /";
      }
    ];
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
        tailscale_ready=0
        for _attempt in {1..30}; do
          if test "$(tailscale status --json 2>/dev/null | jq -r .BackendState 2>/dev/null)" = Running; then
            tailscale_ready=1
            break
          fi
          sleep 1
        done
        if test "$tailscale_ready" != 1; then
          echo "Tailscale did not reach Running state" >&2
          exit 1
        fi
        # Service identities provide Serve endpoints, not operator shells.
        # Recovery enters through Tailscale SSH on Proxmox followed by pct enter.
        # Set false explicitly so restored state cannot retain the old capability.
        tailscale set --ssh=false --accept-routes=false
        # Own the complete Serve configuration, removing obsolete forwards.
        tailscale serve reset
        ${lib.optionalString (
          config.homelab.tailscale.serveTarget != null
        ) "tailscale serve --bg --https=443 ${lib.escapeShellArg config.homelab.tailscale.serveTarget}"}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            path: target:
            "tailscale serve --bg --https=443 --set-path=${lib.escapeShellArg path} ${lib.escapeShellArg target}"
          ) config.homelab.tailscale.serveRoutes
        )}
      '';
    };
  };
}
