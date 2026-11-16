# Relocate upstream's boot-time tmpfiles to an explicitly storage-gated unit.
# This structural adapter fails evaluation if the upstream module shape changes.
# Remove it when upstream exposes a storage-gated directory initialization hook.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  upstream = import (modulesPath + "/services/web-apps/nextcloud.nix") { inherit config lib pkgs; };
  parts = upstream.config.content.contents;
  hasRules = part: part ? systemd.tmpfiles.rules;
  moveRules =
    part:
    if hasRules part then
      part
      // {
        systemd = part.systemd // {
          tmpfiles = builtins.removeAttrs part.systemd.tmpfiles [ "rules" ];
        };
        homelab.nextcloud.directoryRules = part.systemd.tmpfiles.rules;
      }
    else
      part;
in
assert upstream.config._type == "if";
assert upstream.config.content._type == "merge";
assert builtins.length (builtins.filter hasRules parts) == 1;
{
  disabledModules = [ "services/web-apps/nextcloud.nix" ];
  imports = [
    (
      upstream
      // {
        config = lib.mkIf upstream.config.condition (lib.mkMerge (map moveRules parts));
      }
    )
  ];
}
