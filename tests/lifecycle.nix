{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "single-image-operational-target";
  nodes.machine = { lib, ... }: {
    imports = [ ../modules/lifecycle.nix ];
    options.homelab.backup = lib.mkOption {
      type = lib.types.attrs;
      default = {
        enable = true;
        name = "fixture";
      };
    };
    config = {
      homelab.lifecycle.units = [
        "fixture-app"
        "fixture-db"
      ];
      systemd.services = {
        storage-contract = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "mkdir -p /persist";
        };
        operational-ready = {
          requires = [ "storage-contract.service" ];
          after = [ "storage-contract.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "test -f /persist/enrolled";
        };
        fixture-db = {
          requires = [ "operational-ready.service" ];
          after = [ "operational-ready.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "touch /persist/db-started";
        };
        fixture-app = {
          requires = [ "fixture-db.service" ];
          after = [ "fixture-db.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "touch /persist/app-started";
        };
        tailscaled = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "touch /persist/tailscale-started";
        };
        tailscale-policy = {
          requires = [ "tailscaled.service" ];
          after = [ "tailscaled.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "true";
        };
        borgbackup-job-fixture = {
          serviceConfig.Type = "oneshot";
          script = "touch /persist/backup-ran";
        };
      };
      systemd.timers.borgbackup-job-fixture.timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.fail("systemctl is-enabled homelab-operational.target")
    for unit in ["fixture-app", "fixture-db", "tailscaled", "tailscale-policy", "borgbackup-job-fixture.timer"]:
        machine.fail(f"systemctl is-active {unit}")
    machine.fail("systemctl start homelab-operational.target")
    machine.fail("test -e /persist/app-started")
    machine.succeed("touch /persist/enrolled; systemctl reset-failed")
    # Restored/enrolled state does not activate an otherwise fresh root.
    machine.reboot()
    machine.wait_for_unit("multi-user.target")
    machine.fail("systemctl is-active tailscaled fixture-app")
    machine.fail("systemctl start borgbackup-job-fixture")
    machine.fail("test -e /persist/backup-ran")
    # Explicit dependency startup is sufficient for isolated DB restoration.
    machine.succeed("systemctl start fixture-db")
    machine.fail("systemctl is-active fixture-app tailscaled")
    machine.succeed("systemctl stop fixture-db; systemctl reset-failed")
    machine.succeed("systemctl enable --now homelab-operational.target")
    machine.wait_for_unit("homelab-operational.target")
    for unit in ["fixture-app", "fixture-db", "tailscaled", "borgbackup-job-fixture.timer"]:
        machine.wait_for_unit(unit)
    machine.succeed("systemctl start borgbackup-job-fixture; test -e /persist/backup-ran")
    machine.reboot()
    machine.wait_for_unit("homelab-operational.target")
    machine.wait_for_unit("fixture-app")
    machine.succeed("systemctl disable --now homelab-operational.target")
    for unit in ["fixture-app", "fixture-db", "tailscaled", "borgbackup-job-fixture.timer"]:
        machine.fail(f"systemctl is-active {unit}")
    machine.reboot()
    machine.wait_for_unit("multi-user.target")
    machine.fail("systemctl is-active fixture-app tailscaled")
    machine.fail("systemctl is-enabled homelab-operational.target")
  '';
}
