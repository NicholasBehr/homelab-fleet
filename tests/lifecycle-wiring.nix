{ pkgs, configurations }:
let
  lib = pkgs.lib;
  check =
    name: host:
    let
      c = host.config;
      services = c.homelab.lifecycle.units;
      timer = c.homelab.lifecycle.backupJob;
      tree = c.environment.etc."systemd/system".source;
      managedUnits = map (unit: "${unit}.service") services;
      enabledTargetStartsManagedService =
        target:
        target.wantedBy != [ ] && lib.intersectLists managedUnits (target.wants ++ target.requires) != [ ];
    in
    assert lib.all (unit: c.systemd.services.${unit}.wantedBy == [ ]) services;
    assert c.systemd.timers.${timer}.wantedBy == [ ];
    assert !lib.any enabledTargetStartsManagedService (lib.attrValues c.systemd.targets);
    ''
      test ! -e ${tree}/multi-user.target.wants/homelab-operational.target
      test ! -e ${tree}/timers.target.wants/${timer}.timer
      ${lib.optionalString (name == "home-assistant") ''
        test ! -e ${tree}/multi-user.target.wants/home-assistant.target
      ''}
      ${lib.optionalString (name == "immich") ''
        test ! -e ${tree}/multi-user.target.wants/postgresql.target
      ''}
      ${lib.concatMapStringsSep "\n" (unit: ''
        test ! -e ${tree}/multi-user.target.wants/${unit}.service
      '') services}
      grep -q 'Requisite=homelab-operational.target' \
        ${c.systemd.units."${timer}.service".unit}/${timer}.service
      test -x ${c.systemd.generators.homelab-operational-generator}
      grep -q '/var/lib/homelab/operational-enabled' \
        ${c.systemd.generators.homelab-operational-generator}
    '';
in
pkgs.runCommand "service-lifecycle-wiring" { } ''
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList check configurations)}
  touch "$out"
''
