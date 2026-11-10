{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "single-image-operational-target";
  globalTimeout = 300;
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
          path = [ pkgs.systemd ];
          script = ''
            systemctl stop fixture-app tailscaled
            systemctl is-active --quiet homelab-operational.target
            touch /persist/backup-ran
            systemctl start tailscaled fixture-app
          '';
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
    machine.fail("test -e /var/lib/homelab/operational-enabled")
    machine.fail("test -e /run/systemd/generator/multi-user.target.wants/homelab-operational.target")
    for unit in ["fixture-app", "fixture-db", "tailscaled", "tailscale-policy", "borgbackup-job-fixture.timer"]:
        machine.fail(f"systemctl is-active {unit}")
    machine.fail("homelab-activate")
    machine.fail("test -e /var/lib/homelab/operational-enabled")
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
    machine.succeed("homelab-activate")
    machine.succeed("test -L /run/systemd/generator/multi-user.target.wants/homelab-operational.target")
    machine.wait_for_unit("homelab-operational.target")
    for unit in ["fixture-app", "fixture-db", "tailscaled", "borgbackup-job-fixture.timer"]:
        machine.wait_for_unit(unit)
    machine.succeed("systemctl start borgbackup-job-fixture; test -e /persist/backup-ran")
    machine.wait_for_unit("homelab-operational.target")
    machine.wait_for_unit("fixture-app")
    machine.wait_for_unit("tailscaled")
    machine.reboot()
    machine.wait_for_unit("homelab-operational.target")
    machine.wait_for_unit("fixture-app")
    machine.succeed("homelab-deactivate")
    machine.fail("test -e /run/systemd/generator/multi-user.target.wants/homelab-operational.target")
    for unit in ["fixture-app", "fixture-db", "tailscaled", "borgbackup-job-fixture.timer"]:
        machine.fail(f"systemctl is-active {unit}")
    machine.succeed("homelab-activate")
    machine.wait_for_unit("homelab-operational.target")
    machine.wait_for_unit("fixture-app")
    machine.succeed("homelab-deactivate")
    machine.reboot()
    machine.wait_for_unit("multi-user.target")
    machine.fail("systemctl is-active fixture-app tailscaled")
    machine.fail("test -e /var/lib/homelab/operational-enabled")
  '';
}
