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
        "tailscaled"
        "tailscale-policy"
      ];
      homelab.lifecycle.backupJob = "borgbackup-job-fixture";
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
          path = [
            pkgs.systemd
            pkgs.util-linux
          ];
          script = ''
            mkdir -p /run/homelab-backup
            exec 8>/run/homelab-backup/operation.lock
            flock -n 8
            systemctl is-active --quiet homelab-operational.target
            if test -e /persist/hold-backup; then
              touch /run/backup-held
              while test -e /persist/hold-backup; do sleep 1; done
            fi
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
    # Run the real activation script with an isolated marker and a failing reload.
    machine.succeed('mkdir -p /tmp/reload-fixture/bin; printf "%s\\n" "#!/bin/sh" \'echo "$*" >> /tmp/reload-fixture/events\' \'test "$1" != daemon-reload\' > /tmp/reload-fixture/bin/systemctl; chmod +x /tmp/reload-fixture/bin/systemctl')
    machine.succeed("sed -e 's@${pkgs.systemd}/bin@/tmp/reload-fixture/bin@g' -e 's@/var/lib/homelab@/tmp/reload-fixture/state@g' $(command -v homelab-activate) > /tmp/reload-fixture/activate; chmod +x /tmp/reload-fixture/activate")
    machine.fail("/tmp/reload-fixture/activate")
    machine.fail("test -e /tmp/reload-fixture/state/operational-enabled")
    machine.succeed("grep -q '^stop homelab-operational.target$' /tmp/reload-fixture/events")
    machine.fail("homelab-activate")
    machine.fail("test -e /var/lib/homelab/operational-enabled")
    for unit in ["fixture-app", "fixture-db", "tailscaled", "tailscale-policy", "borgbackup-job-fixture.timer"]:
        machine.fail(f"systemctl is-active {unit}")
    machine.fail("test -e /persist/app-started")
    machine.succeed("touch /persist/enrolled; systemctl reset-failed")
    # Restored/enrolled state does not activate an otherwise fresh root.
    machine.shutdown()
    machine.start()
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
    # Simulate shutdown owning the coordination lock while a manual job starts.
    machine.succeed("rm /persist/backup-ran; systemd-run --unit=lock-holder ${pkgs.util-linux}/bin/flock -x /run/homelab-backup/operation.lock ${pkgs.coreutils}/bin/sleep 30")
    machine.succeed("systemctl is-active --quiet lock-holder")
    machine.fail("systemctl start borgbackup-job-fixture")
    machine.fail("test -e /persist/backup-ran")
    machine.wait_for_unit("fixture-app")
    machine.succeed("systemctl stop lock-holder; systemctl reset-failed borgbackup-job-fixture")
    # A running backup prevents deactivation; stopping the timer prevents another.
    machine.succeed("touch /persist/hold-backup; systemctl start --no-block borgbackup-job-fixture")
    machine.wait_for_file("/run/backup-held")
    machine.fail("homelab-deactivate")
    machine.fail("systemctl is-active borgbackup-job-fixture.timer")
    machine.succeed("test -e /var/lib/homelab/operational-enabled; systemctl is-active --quiet homelab-operational.target; rm /persist/hold-backup")
    machine.wait_until_succeeds("! systemctl is-active --quiet borgbackup-job-fixture")
    machine.succeed("systemctl start borgbackup-job-fixture.timer")
    machine.shutdown()
    machine.start()
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
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.fail("systemctl is-active fixture-app tailscaled")
    machine.fail("test -e /var/lib/homelab/operational-enabled")
  '';
}
