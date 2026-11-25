{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.tailscale;
  routes = cfg.serveRoutes // lib.optionalAttrs (cfg.serveTarget != null) { "/" = cfg.serveTarget; };
  start = pkgs.writeShellScript "tailnet-https-start" ''
    set -euo pipefail
    umask 077
    status="$(${pkgs.tailscale}/bin/tailscale status --json)"
    name="$(printf '%s' "$status" | ${pkgs.jq}/bin/jq -er '.Self.DNSName | rtrimstr(".")')"
    address="$(${pkgs.tailscale}/bin/tailscale ip -4)"
    [[ $name =~ ^[a-z0-9-]+(\.[a-z0-9-]+)+\.ts\.net$ ]] || exit 1
    [[ $address =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
    {
      printf '{\n admin off\n auto_https disable_redirects\n servers {\n protocols h1 h2\n }\n}\n%s {\n bind %s\n' "$name" "$address"
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          path: target:
          "printf '%s\\n' "
          + lib.escapeShellArg (
            let
              upstream = builtins.head (builtins.match "(http://127\\.0\\.0\\.1:[0-9]+)(/.*)?" target);
            in
            if path == "/" then
              "handle {\n reverse_proxy ${upstream}\n}"
            else
              "redir ${path} ${path}/ 308\n handle ${path}/* {\n reverse_proxy ${upstream}\n}"
          )
        ) routes
      )}
      printf '}\n'
    } > /run/tailnet-https/Caddyfile
    exec ${pkgs.caddy}/bin/caddy run --config /run/tailnet-https/Caddyfile --adapter caddyfile
  '';
in
{
  config = lib.mkIf (routes != { }) {
    assertions = [
      {
        assertion = builtins.all (
          path:
          let
            parts = builtins.match "http://127\\.0\\.0\\.1:[0-9]+(/.*)?" routes.${path};
          in
          parts != null && (builtins.head parts == null || builtins.head parts == "${path}/")
        ) (builtins.attrNames routes);
        message = "Tailnet HTTPS upstream path must match its public route prefix";
      }
      {
        assertion = builtins.all (path: builtins.match "/[a-zA-Z0-9/_-]*" path != null) (
          builtins.attrNames routes
        );
        message = "Tailnet HTTPS route paths must contain only URL path characters";
      }
      {
        assertion = builtins.all (
          target: builtins.match "http://127\\.0\\.0\\.1:[0-9]+(/[a-zA-Z0-9/_-]*)?" target != null
        ) (builtins.attrValues routes);
        message = "Tailnet HTTPS upstreams must be loopback HTTP endpoints";
      }
    ];
    services.caddy = {
      enable = true;
      enableReload = false;
      openFirewall = false;
    };
    homelab.lifecycle.units = [ "caddy" ];
    homelab.health.units = [ "caddy" ];
    systemd.services.tailscaled = {
      environment.TS_PERMIT_CERT_UID = "caddy";
      wants = [ "caddy.service" ];
    };
    systemd.services.caddy = {
      partOf = [ "tailscaled.service" ];
      requires = [ "tailscale-policy.service" ];
      bindsTo = [ "tailscaled.service" ];
      after = [
        "tailscaled.service"
        "tailscale-policy.service"
      ];
      environment = {
        XDG_DATA_HOME = "/run/tailnet-https/data";
        XDG_CONFIG_HOME = "/run/tailnet-https/config";
      };
      serviceConfig = {
        ExecStart = lib.mkForce start;
        RuntimeDirectory = "tailnet-https";
        RuntimeDirectoryMode = "0700";
        ReadWritePaths = [ "/run/tailnet-https" ];
        AmbientCapabilities = [
          ""
          "CAP_NET_BIND_SERVICE"
        ];
        CapabilityBoundingSet = [
          ""
          "CAP_NET_BIND_SERVICE"
        ];
        UMask = "0077";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
