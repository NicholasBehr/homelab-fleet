{ pkgs, configurations }:
let
  lib = pkgs.lib;
  check =
    name: host:
    let
      c = host.config;
      services = c.homelab.lifecycle.units ++ [
        "tailscaled"
        "tailscale-policy"
      ];
      timer = "borgbackup-job-${c.homelab.backup.name}";
      tree = c.environment.etc."systemd/system".source;
    in
    assert lib.all (unit: c.systemd.services.${unit}.wantedBy == [ ]) services;
    assert c.systemd.timers.${timer}.wantedBy == [ ];
    ''
      test -L ${tree}/multi-user.target.wants/homelab-operational.target
      test ! -e ${tree}/timers.target.wants/${timer}.timer
      ${lib.concatMapStringsSep "\n" (unit: ''
        test ! -e ${tree}/multi-user.target.wants/${unit}.service
      '') services}
      grep -q 'Requisite=homelab-operational.target' \
        ${c.systemd.units."${timer}.service".unit}/${timer}.service
      grep -q 'ConditionPathExists=/var/lib/homelab/operational-enabled' \
        ${c.systemd.units."homelab-operational.target".unit}/homelab-operational.target
    '';
in
pkgs.runCommand "service-lifecycle-wiring" { } ''
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList check configurations)}
  touch "$out"
''
