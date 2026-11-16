{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "nextcloud-private-backup-restore";
  globalTimeout = 900;
  nodes.machine = { lib, ... }: {
    imports = [ ../../../deployments/nextcloud.nix ];
    disabledModules = [
      ../../../modules/proxmox-lxc.nix
      ../../../modules/tailscale.nix
    ];
    # No network enrollment or production credentials in CI.
    options.homelab.tailscale.serveTarget = lib.mkOption { type = lib.types.str; };
    config = {
      users.users.root.hashedPassword = lib.mkForce null;
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        emptyDiskImages = [
          2048
          4096
        ];
      };
      homelab.backup = {
        repositoryFile = lib.mkForce null;
        repository = "/var/lib/nextcloud-test-repository";
        schedule = lib.mkForce "2099-01-01 00:00:00";
      };
      systemd.services = {
        tailscaled = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "true";
        };
        tailscale-policy = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "true";
        };
      };
      environment.systemPackages = [ pkgs.acl ];
    };
  };
  testScript = ''
    import json
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.fail("test -e /var/lib/homelab/operational-enabled")
    machine.fail("systemctl start nextcloud-directories")
    machine.fail("test -e /persist/nextcloud/config/config.php")
    machine.fail("systemctl is-active --quiet phpfpm-nextcloud")
    # These two disks were created solely by this test's emptyDiskImages.
    machine.succeed("mkfs.ext4 -F /dev/vdb; mkfs.ext4 -F /dev/vdc; mkdir -p /persist /data; mount /dev/vdb /persist; mount /dev/vdc /data")
    machine.succeed("printf homelab-nextcloud-persist-v1 > /persist/.homelab-volume; printf homelab-nextcloud-data-v1 > /data/.homelab-volume")
    machine.succeed("install -d -m 0700 /persist/secrets; umask 077; printf synthetic-test-passphrase > /persist/secrets/borg-passphrase; printf synthetic-test-key > /persist/secrets/borg-ssh-key")
    machine.succeed("umask 077; printf '%s' '{\"trusted_domains\":[\"localhost\",\"127.0.0.1\",\"fixture.example.ts.net\"],\"overwrite.cli.url\":\"https://fixture.example.ts.net\"}' > /persist/secrets/nextcloud-settings.json")
    machine.succeed("systemctl reset-failed; nextcloud-initialize")
    machine.fail("nextcloud-initialize")
    # Synthetic password transport is permitted in fixtures only.
    machine.succeed("nextcloud-occ maintenance:mode --off; OC_PASS=synthetic-client-password nextcloud-occ user:add --password-from-env --group=admin fixture")
    machine.succeed("nextcloud-occ user:setting fixture files quota 20MB")
    machine.succeed("systemctl stop redis-nextcloud postgresql")
    machine.succeed("mv /persist/postgresql/17/PG_VERSION /persist/postgresql/17/PG_VERSION.retained")
    machine.fail("homelab-activate")
    machine.fail("test -e /persist/postgresql/17/PG_VERSION")
    machine.succeed("mv /persist/postgresql/17/PG_VERSION.retained /persist/postgresql/17/PG_VERSION; systemctl reset-failed")
    machine.succeed("borg-job-nextcloud init --encryption=repokey-blake2; homelab-activate")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("nextcloud-cron.timer")
    status = json.loads(machine.succeed("curl -fsS http://127.0.0.1:8080/status.php"))
    assert status["installed"] and not status["maintenance"]
    machine.succeed("printf 'original fixture bytes' > /tmp/original; curl --fail -u fixture:synthetic-client-password -T /tmp/original http://127.0.0.1:8080/remote.php/dav/files/fixture/restore.txt")
    machine.succeed("curl --fail -u fixture:synthetic-client-password http://127.0.0.1:8080/remote.php/dav/files/fixture/restore.txt -o /tmp/download; cmp /tmp/original /tmp/download")
    machine.succeed("dd if=/dev/zero of=/tmp/over-quota bs=1M count=21")
    quota_status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -u fixture:synthetic-client-password -T /tmp/over-quota http://127.0.0.1:8080/remote.php/dav/files/fixture/too-large").strip()
    assert quota_status == "507", quota_status
    machine.succeed("systemctl start borgbackup-job-nextcloud; borg-job-nextcloud check --verify-data")
    machine.wait_for_unit("nginx.service")
    machine.succeed("test ! -e /run/homelab-backup/restart")
    archive = machine.succeed("borg-job-nextcloud list --short").strip().splitlines()[-1]
    listing = machine.succeed(f"borg-job-nextcloud list --short ::{archive}")
    assert "data/nextcloud/fixture/files/restore.txt" in listing
    assert "persist/backup/nextcloud.dump" in listing
    assert "persist/postgresql/17/PG_VERSION" not in listing
    assert "data/nextcloud-tmp" not in listing
    machine.succeed("homelab-deactivate")
    machine.fail("systemctl is-active --quiet nextcloud-cron.timer")
    machine.fail("systemctl is-active --quiet phpfpm-nextcloud")
    # Preserve the originals; restore into empty application paths, not running state.
    machine.succeed("mv /persist/nextcloud /persist/retained-nextcloud; mv /persist/postgresql /persist/retained-postgresql; mv /data/nextcloud /data/retained-nextcloud")
    machine.succeed(f"cd /; borg-job-nextcloud extract ::{archive} persist/nextcloud data/nextcloud persist/backup")
    machine.succeed("systemctl start nextcloud-directories postgresql-setup redis-nextcloud")
    # A pristine NixOS database has a public schema; restore objects under its owner.
    machine.succeed("runuser -u postgres -- pg_restore --single-transaction --exit-on-error --no-owner --no-privileges --role=nextcloud --dbname=nextcloud /persist/backup/nextcloud.dump")
    machine.succeed("nextcloud-occ status --output=json")
    machine.succeed("nextcloud-occ maintenance:mode --off; systemctl stop redis-nextcloud postgresql; homelab-activate")
    machine.wait_for_unit("nginx.service")
    machine.succeed("curl --fail -u fixture:synthetic-client-password http://127.0.0.1:8080/remote.php/dav/files/fixture/restore.txt -o /tmp/restored; cmp /tmp/original /tmp/restored")
    assert machine.succeed("nextcloud-occ user:setting fixture files quota").strip() == "20MB"
    machine.succeed("systemctl start borgbackup-job-nextcloud")
  '';
}
