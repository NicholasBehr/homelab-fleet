{
  pkgs,
  nixpkgs,
  fixture,
}:
let
  httpsFixture =
    (fixture.extendModules {
      modules = [
        {
          homelab.tailscale.serveTarget = "http://127.0.0.1:8080";
          homelab.tailscale.serveRoutes."/example" = "http://127.0.0.1:8081/example/";
        }
      ];
    }).config;
  tailscalePolicy = pkgs.writeText "tailscale-policy" fixture.config.systemd.services.tailscale-policy.script;
  secretFixture =
    (fixture.extendModules {
      modules = [
        {
          homelab.secrets.requiredFiles = [ "/persist/secrets/fixture" ];
        }
      ];
    }).config;
in
{
  tailnet-https =
    assert httpsFixture.services.caddy.openFirewall == false;
    assert builtins.elem "operational-ready.service" httpsFixture.systemd.services.caddy.requires;
    assert builtins.elem "tailscaled.service" httpsFixture.systemd.services.caddy.bindsTo;
    assert builtins.elem "caddy.service" httpsFixture.systemd.services.tailscaled.wants;
    assert httpsFixture.systemd.services.caddy.wantedBy == [ ];
    pkgs.runCommand "tailnet-https-config" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
      shellcheck ${httpsFixture.systemd.services.caddy.serviceConfig.ExecStart}
      touch "$out"
    '';
  # Exercise all matching tmpfiles z rules: they accumulate, rather than
  # selecting only the first file's rule for a path.
  tun-permissions =
    pkgs.runCommand "container-tun-permissions" { nativeBuildInputs = [ pkgs.systemd ]; }
      ''
        mkdir -p root/etc/tmpfiles.d root/dev/net
        printf 'root:x:%s:%s::/:/bin/sh\n' "$(id -u)" "$(id -g)" > root/etc/passwd
        printf 'root:x:%s:\n' "$(id -g)" > root/etc/group
        cp ${fixture.config.environment.etc."tmpfiles.d/static-nodes-permissions.conf".source} \
          root/etc/tmpfiles.d/static-nodes-permissions.conf
        cat > root/etc/tmpfiles.d/00-nixos.conf <<'RULES'
        ${nixpkgs.lib.concatStringsSep "\n" fixture.config.systemd.tmpfiles.rules}
        RULES
        touch root/dev/net/tun
        chmod 0666 root/dev/net/tun
        systemd-tmpfiles --root="$PWD/root" --create --prefix=/dev/net/tun
        test "$(stat -c '%a' root/dev/net/tun)" = 600
        touch "$out"
      '';
  shared-modules = fixture.config.system.build.toplevel;
  operator-shell = pkgs.runCommand "operator-shell-wiring" { } ''
    grep -Fq 'L+ /bin/bash - - - - ${pkgs.bashInteractive}/bin/bash' \
      ${pkgs.writeText "tmpfiles-rules" (
        nixpkgs.lib.concatStringsSep "\n" fixture.config.systemd.tmpfiles.rules
      )}
    test -x ${pkgs.bashInteractive}/bin/bash
    touch "$out"
  '';
  container-access = pkgs.runCommand "container-access-policy" { } ''
    grep -Fq 'for _attempt in {1..30}' ${tailscalePolicy}
    grep -Fq 'Tailscale did not reach Running state' ${tailscalePolicy}
    grep -Fq 'tailscale set --ssh=false --accept-routes=false' ${tailscalePolicy}
    ! grep -Fq -- '--ssh=true' ${tailscalePolicy}
    touch "$out"
  '';
  runtime-secret-service = pkgs.runCommand "runtime-secret-service-wiring" { } ''
    grep -q 'Requires=.*storage-contract.service' \
      ${secretFixture.systemd.units."operational-ready.service".unit}/operational-ready.service
    grep -q 'After=.*storage-contract.service' \
      ${secretFixture.systemd.units."operational-ready.service".unit}/operational-ready.service
    grep -q '/persist/secrets/fixture' \
      ${pkgs.writeText "ready-script" secretFixture.systemd.services.operational-ready.script}
    touch "$out"
  '';
}
