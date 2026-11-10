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
  marker = "/var/lib/homelab/operational-enabled";
  activate = pkgs.writeShellApplication {
    name = "homelab-activate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      install -d -m 0700 /var/lib/homelab
      record=$(mktemp /var/lib/homelab/.operational-enabled.XXXXXX)
      trap 'rm -f "$record"' EXIT
      printf '1\n' >"$record"
      chmod 0600 "$record"
      mv -T "$record" ${marker}
      if ! systemctl start homelab-operational.target; then
        rm -f ${marker}
        systemctl stop homelab-operational.target || true
        exit 1
      fi
    '';
  };
  deactivate = pkgs.writeShellApplication {
    name = "homelab-deactivate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      if systemctl is-active --quiet ${job}; then
        echo 'Refusing to deactivate while the backup job is active' >&2
        exit 1
      fi
      rm -f ${marker}
      systemctl stop homelab-operational.target
    '';
  };
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
    environment.systemPackages = [
      activate
      deactivate
    ];
    # The target is declaratively part of boot, but the root-local condition keeps
    # a fresh image inert. Restored /persist state can never satisfy this gate.
    systemd.targets."homelab-operational" = {
      description = "Explicitly activated homelab workload";
      unitConfig.ConditionPathExists = marker;
      requires = [
        "storage-contract.service"
        "operational-ready.service"
      ];
      wants = map (name: "${name}.service") startup ++ timer;
      after = [
        "storage-contract.service"
        "operational-ready.service"
      ]
      ++ map (name: "${name}.service") startup;
      wantedBy = [ "multi-user.target" ];
    };
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
