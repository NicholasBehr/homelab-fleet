{
  pkgs,
  home-assistant,
}:
let
  backupFixture =
    (home-assistant.extendModules {
      modules = [
        {
          homelab.backup = {
            enable = true;
            repository = "/tmp/disposable-test-repository";
            repositoryFile = pkgs.lib.mkForce null;
          };
        }
      ];
    }).config;
in
{
  backup-config = backupFixture.system.build.toplevel;
  service-config =
    assert home-assistant.config.services.home-assistant.configDir == "/persist/home-assistant";
    assert home-assistant.config.services.home-assistant.openFirewall == false;
    assert home-assistant.config.services.home-assistant.openFirewallForComponents == false;
    assert home-assistant.config.services.home-assistant.extraComponents == [
      "zha"
      "smlight"
    ];
    pkgs.runCommand "home-assistant-service-config" { } ''
      grep -q 'Requires=.*operational-ready.service' \
        ${home-assistant.config.systemd.units."home-assistant.service".unit}/home-assistant.service
      grep -q '127.0.0.1' \
        ${pkgs.writeText "home-assistant-config" (builtins.toJSON home-assistant.config.services.home-assistant.config)}
      grep -q 'home-assistant' \
        ${pkgs.writeText "home-assistant-versions" home-assistant.config.environment.etc."homelab-versions.json".text}
      touch "$out"
    '';
  system = home-assistant.config.system.build.toplevel;
}
