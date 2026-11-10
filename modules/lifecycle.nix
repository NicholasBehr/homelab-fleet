{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.lifecycle;
  backup = config.homelab.backup;
  startup = lib.unique (
    cfg.units
    ++ [
      "tailscaled"
      "tailscale-policy"
    ]
  );
  job = "borgbackup-job-${backup.name}";
  timer = lib.optional backup.enable "${job}.timer";
in
{
  options.homelab.lifecycle = {
    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Application and dependency units started by explicit operational activation.";
    };
  };
  config = {
    # NixOS normally symlinks the entire unit directory into the store. Keep its
    # generated units immutable but materialize directories so systemctl enable
    # writes only root-local enablement links. Disposable-root replacement resets
    # these links; no mutable unit state is restored from /persist.
    environment.etc."systemd/system".enable = false;
    system.activationScripts.homelab-unit-directory = {
      deps = [ "etc" ];
      text = ''
        umask 022
        if test -L /etc/systemd/system; then
          echo 'Unexpected legacy unit directory: use a fresh root image' >&2
          exit 1
        fi
        install -d -m 0755 /etc/systemd/system
        ${pkgs.coreutils}/bin/cp --recursive --symbolic-link --update=none --no-preserve=mode \
          ${config.environment.etc."systemd/system".source}/. /etc/systemd/system/
        # disable removes linked unit files too. Keep this installable target a
        # regular root-local file so it can be re-enabled without rebooting.
        target=$(mktemp /etc/systemd/system/.homelab-operational.XXXXXX)
        install -m 0644 ${
          config.environment.etc."systemd/system".source
        }/homelab-operational.target "$target"
        mv -Tf "$target" /etc/systemd/system/homelab-operational.target
      '';
    };
    # Raw text supplies [Install] without NixOS's wantedBy, which would enable it
    # declaratively in every image. Operators create that link with systemctl.
    systemd.units."homelab-operational.target".text = ''
      [Unit]
      Description=Explicitly activated homelab workload
      Requires=storage-contract.service operational-ready.service ${
        lib.concatMapStringsSep " " (name: "${name}.service") startup
      }
      Wants=${lib.concatStringsSep " " timer}
      After=storage-contract.service operational-ready.service ${
        lib.concatMapStringsSep " " (name: "${name}.service") startup
      }

      [Install]
      WantedBy=multi-user.target
    '';
    systemd.services = lib.mkMerge [
      {
        tailscaled = {
          requires = [ "operational-ready.service" ];
          after = [ "operational-ready.service" ];
        };
      }
      (lib.genAttrs startup (_: {
        wantedBy = lib.mkForce [ ];
        partOf = [ "homelab-operational.target" ];
      }))
      (lib.optionalAttrs backup.enable {
        ${job} = {
          partOf = [ "homelab-operational.target" ];
          # A persistent timer or manual request must not run the job during a
          # restore. Starting the target is the explicit activation boundary.
          requisite = [ "homelab-operational.target" ];
          after = [ "homelab-operational.target" ];
        };
      })
    ];
    systemd.timers = lib.optionalAttrs backup.enable {
      ${job} = {
        wantedBy = lib.mkForce [ ];
        partOf = [ "homelab-operational.target" ];
      };
    };
  };
}
