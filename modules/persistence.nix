{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.storage;
in
{
  options.homelab.storage = {
    volumes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption { type = lib.types.strMatching "/.+"; };
            marker = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
    };
    directories = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "/persist(/.*)?");
      default = [ ];
    };
  };
  config = {
    assertions = [
      {
        assertion =
          builtins.length (lib.unique (map (v: v.path) cfg.volumes)) == builtins.length cfg.volumes;
        message = "Persistent mount paths must be unique";
      }
      {
        assertion =
          builtins.length (lib.unique (map (v: v.marker) cfg.volumes)) == builtins.length cfg.volumes;
        message = "Persistent mount markers must be unique";
      }
      {
        assertion = builtins.length cfg.volumes >= 1;
        message = "Declare persistent mount identities";
      }
    ];
    environment.etc."homelab-storage.json".text = builtins.toJSON cfg.volumes;
    systemd.services.storage-contract = {
      description = "Verify declared persistent mounts before stateful services";
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.util-linux
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script =
        lib.concatMapStringsSep "\n" (
          v:
          "${pkgs.bash}/bin/bash ${../scripts/verify-storage} ${lib.escapeShellArg v.path} ${lib.escapeShellArg v.marker}"
        ) cfg.volumes
        + "\n"
        + lib.optionalString (cfg.directories != [ ]) (
          "install -d -m 0700 " + lib.escapeShellArgs cfg.directories
        );
    };
    systemd.services.tailscaled = {
      requires = [ "storage-contract.service" ];
      after = [ "storage-contract.service" ];
    };
  };
}
