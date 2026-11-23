{
  pkgs,
  paperlessNixpkgs,
}:
pkgs.testers.runNixOSTest {
  name = "paperless-ngx-private-backup-restore";
  globalTimeout = 1200;
  node.specialArgs = { inherit paperlessNixpkgs; };
  nodes.machine = { lib, ... }: {
    imports = [ ../../../deployments/paperless-ngx.nix ];
    disabledModules = [
      ../../../modules/proxmox-lxc.nix
      ../../../modules/tailscale.nix
    ];
    options.homelab.tailscale.serveTarget = lib.mkOption { type = lib.types.str; };
    config = {
      users.users.root.hashedPassword = lib.mkForce null;
      virtualisation = {
        memorySize = 6144;
        cores = 4;
        emptyDiskImages = [ 6144 ];
      };
      homelab.backup = {
        repositoryFile = lib.mkForce null;
        repository = "/var/lib/paperless-test-repository";
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
      environment.systemPackages = [ pkgs.ghostscript_headless ];
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.fail("test -e /var/lib/homelab/operational-enabled")
    machine.fail("systemctl start paperless-web")
    machine.fail("test -e /persist/paperless/.initialized")

    # This disk is created solely by this test's emptyDiskImages declaration.
    machine.succeed("mkfs.ext4 -F /dev/vdb; mkdir -p /persist; mount /dev/vdb /persist")
    machine.succeed("printf homelab-paperless-ngx-persist-v1 > /persist/.homelab-volume")
    machine.succeed("install -d -m 0700 /persist/secrets; umask 077; printf synthetic-test-passphrase > /persist/secrets/borg-passphrase; printf synthetic-test-key > /persist/secrets/borg-ssh-key")
    machine.succeed("umask 077; printf 'PAPERLESS_URL=https://paperless-fixture.example.ts.net\\n' > /persist/secrets/paperless.env")
    machine.succeed("systemctl reset-failed")
    machine.succeed("DJANGO_SUPERUSER_USERNAME=fixture DJANGO_SUPERUSER_EMAIL=fixture@example.invalid DJANGO_SUPERUSER_PASSWORD=synthetic-client-password paperless-initialize --noinput")
    machine.fail("paperless-initialize --noinput")
    machine.succeed("borg-job-paperless-ngx init --encryption=repokey-blake2; homelab-activate")
    machine.wait_for_unit("paperless-web.service", timeout=300)
    machine.wait_until_succeeds("curl -fsS http://localhost:28981/ >/dev/null", timeout=120)

    machine.succeed("gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sOutputFile=/tmp/fixture.pdf -c '/Helvetica findfont 24 scalefont setfont 72 720 moveto (restore fixture) show showpage'")
    machine.succeed("cp /tmp/fixture.pdf /persist/paperless/consume/restore-fixture.pdf")
    machine.wait_until_succeeds("paperless-manage shell -c 'from documents.models import Document; assert Document.objects.count() == 1'", timeout=300)
    machine.succeed("systemctl start borgbackup-job-paperless-ngx")
    machine.wait_until_succeeds("test $(systemctl show borgbackup-job-paperless-ngx -p ActiveState --value) = inactive", timeout=300)
    machine.succeed("test $(systemctl show borgbackup-job-paperless-ngx -p Result --value) = success; borg-job-paperless-ngx check --verify-data")
    archive = machine.succeed("borg-job-paperless-ngx list --short").strip()
    listing = machine.succeed(f"borg-job-paperless-ngx list --short ::{archive}")
    assert "persist/backup/paperless.dump" in listing
    assert "persist/paperless/media/documents/originals" in listing
    assert "persist/postgresql/17/PG_VERSION" not in listing

    machine.succeed("homelab-deactivate")
    machine.fail("systemctl is-active --quiet paperless-web")
    machine.succeed("mv /persist/paperless /persist/retained-paperless; mv /persist/postgresql /persist/retained-postgresql")
    machine.succeed(f"cd /; borg-job-paperless-ngx extract ::{archive} persist/paperless persist/backup")
    machine.succeed("systemctl start paperless-directories postgresql-setup redis-paperless paperless-secret-key")
    machine.succeed("test $(stat -c '%a:%U' /persist/backup/paperless.dump) = 600:root")
    machine.fail("runuser -u postgres -- test -r /persist/backup/paperless.dump")
    machine.succeed("runuser -u postgres -- pg_restore --single-transaction --exit-on-error --no-owner --no-privileges --role=paperless --dbname=paperless < /persist/backup/paperless.dump")
    machine.succeed("systemctl stop redis-paperless postgresql; homelab-activate")
    machine.wait_for_unit("paperless-web.service", timeout=300)
    machine.succeed("paperless-manage shell -c 'from documents.models import Document; d=Document.objects.get(); assert d.original_filename == \"restore-fixture.pdf\"'")
    machine.succeed("systemctl start borgbackup-job-paperless-ngx")
    machine.wait_until_succeeds("test $(systemctl show borgbackup-job-paperless-ngx -p ActiveState --value) = inactive", timeout=300)
    machine.succeed("test $(systemctl show borgbackup-job-paperless-ngx -p Result --value) = success")
  '';
}
