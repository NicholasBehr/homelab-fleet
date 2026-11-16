# Private Nextcloud MVP

Two initial accounts (administrator and ordinary user), iOS/macOS clients and
individual files up to 10 GB. Browser, sync and WebDAV access are Tailscale-only.
No Funnel, Cloudflare, public links, external storage, per-user mounts or
impermanence. Nextcloud 34 is explicitly selected from pinned nixpkgs; apps cannot
update themselves. Use native file quotas; previews, versions and trash consume
additional physical space. Retention caps versions/trash at 30 days.

## Storage and resources

The proposed contract uses 2 CPUs, 4 GiB RAM, 32 GiB disposable root, 128 GiB NVMe
`/persist`, and 932 GiB `/data` (approximately one decimal TB, quota not reserved
capacity). Allocation requires live provenance/capacity discovery and approval.

| Path | Contents |
|---|---|
| `/data/nextcloud` | Complete Nextcloud application data, including `.ocdata`, originals, app data, previews, versions, trash and chunk uploads |
| `/data/nextcloud-tmp/{php,nginx-body,nginx-fastcgi}` | Disposable PHP and Nginx buffering; excluded from backup |
| `/persist/nextcloud/config` | Mutable `config.php` identity/state and image-generated override symlink |
| `/persist/postgresql/17` | Live PostgreSQL; excluded from file backups |
| `/persist/redis` | Disposable locks/cache, no durable Redis snapshots |
| `/persist/secrets/nextcloud-settings.json` | Root-only runtime tailnet endpoint settings |
| `/persist/backup/{nextcloud.dump,versions.json}` | Completed logical dump and version record |
| `/persist/{tailscale,secrets,borg}` | Network identity, enrolled backup credentials and Borg state |

This service explicitly permits previews and all other application data on
`/data`. Only that volume may move to HDD. PostgreSQL, configuration and operational
identity remain on NVMe. No automatic tiering or migration. Reserve free space for
multiple concurrent 10 GB uploads and assembly; user quotas are not physical-volume
limits. The configured upload ceiling is 10 GiB, covering decimal 10 GB files.

Application UID/GID is 1130, PostgreSQL 71; Redis runs as the Nextcloud user. Outer
volume markers are `homelab-nextcloud-persist-v1` and `homelab-nextcloud-data-v1`.
Always verify creation provenance and attachments separately: markers are not
storage authorization. Keep the parent volumes root-owned and service state owned
by the declared application users.

## Enrollment and initial accounts

Use the generic [lifecycle](lifecycle.md) and [recovery](recovery.md) procedures.
Enroll distinct Borg credentials and independently verify the `borg-nextcloud`
Document in the `Homelab` vault. Nextcloud also requires this JSON, installed with
root:root mode0600 under root:root mode0700 `/persist/secrets`, using the same
verified-volume, no-symlink, no-overwrite enrollment procedure:

```json
{
  "trusted_domains": ["localhost", "127.0.0.1", "nextcloud.example.ts.net"],
  "overwrite.cli.url": "https://nextcloud.example.ts.net"
}
```

Replace the example with the enrolled node's actual Tailscale DNS name. This file
contains no password, but remains protected and excluded from public source. Its
schema is restricted to these two keys. Tailscale enrollment may use the documented
console helper workflow; never activate a duplicate restored identity.

On a verified fresh instance, with the operational target inactive:

1. Run `nextcloud-initialize` from the authenticated root console. It refuses an
   activation record, existing config/data, or nonempty database. It starts only
   directory, database and Redis helpers, uses PostgreSQL peer authentication, and
   installs without an administrator. It leaves maintenance enabled.
2. Run `nextcloud-occ maintenance:mode --off`, then
   `nextcloud-occ user:add --group=admin admin` and `nextcloud-occ user:add USER`.
   Enter passwords only at the commands' hidden terminal prompts. Do not use
   `--password-from-env`, plaintext arguments, chat or clipboard for real passwords.
   No HTTP service is running during this step. Set ordinary-user quota with
   `nextcloud-occ user:setting USER files quota 800GB` (example; choose deliberately).
3. Stop `redis-nextcloud` and `postgresql` helpers. Complete the synthetic recovery
   rehearsal and identity checks, then run `homelab-activate`.
4. Verify the private HTTPS endpoint, enroll iOS/macOS clients using revocable app
   passwords as appropriate, run the first native backup and independently restore
   representative data before storing irreplaceable files.

If initialization fails, stop helpers and investigate. Do not delete configuration
or rerun installation over partial state. Recovery always uses restored state,
never `nextcloud-initialize`. Users are application accounts, not Linux accounts.

## Backup and restoration

At 03:00 Europe/Zurich, the native Borg job records maintenance/restart intent,
enables maintenance, stops cron/database-maintenance work and HTTP/PHP workers,
then creates an atomic custom-format PostgreSQL dump. Redis and Tailscale are
stopped before Borg reads `/persist` and `/data/nextcloud`. Live PostgreSQL, Redis,
Borg cache, incomplete dumps and external temporary buffers are excluded. Keep the
application offline throughout Borg; overnight downtime is accepted. Do not prune
upload directories from inside the application data tree in the MVP.

Cleanup attempts all restarts, restores the pre-backup maintenance state and retains
intent after failure. Do not clear another operation's maintenance flag. Power loss
cannot run cleanup; check maintenance, service state and backup freshness after
reboot. Existing operator maintenance is intentionally preserved.

Run `systemctl start borgbackup-job-nextcloud` for the first backup. Use the existing
36-hour freshness check. Run `borg-job-nextcloud check --verify-data` monthly and
before a migration/recovery; this reads the archived data and may take considerable
time. Do not run automatic `--repair`. Repository checks do not replace restores.
Keep the fleet's independently controlled provider snapshots and recovery escrow.

Restore the exact compatible image and these paths from ONE verified archive onto
fresh, recorded volumes, preserving outer markers:

- `persist/nextcloud` and `data/nextcloud`;
- `persist/backup/nextcloud.dump` and `persist/backup/versions.json`;
- `persist/secrets`, Borg config/trust/runtime endpoint;
- `persist/tailscale` only after establishing identity exclusivity.

Do not restore PostgreSQL's live directory, Redis state, temporary buffers or the
root-local activation record. Keep the operational target and all app listeners
inactive. Start only `nextcloud-directories`, `postgresql-setup` (which starts PostgreSQL) and `redis-nextcloud`;
these are the explicitly permitted restoration helpers. They require verified
volumes and enrolled runtime files, but do not activate HTTP or background jobs.
They recreate the generated configuration symlink for the matching image.

With the fresh empty `nextcloud` database and role created by NixOS:

```sh
runuser -u postgres -- pg_restore --single-transaction --exit-on-error \
  --no-owner --no-privileges --role=nextcloud --dbname=nextcloud \
  /persist/backup/nextcloud.dump
```

Stop on any error; never drop production/recovery databases as an automatic retry.
Validate account/file counts, markers, ownership and representative checksums. An
outdated recovery may require `nextcloud-occ maintenance:data-fingerprint` before
clients reconnect; assess this deliberately because it changes client reconciliation
and can cause conflicts. Disable the restored backup maintenance flag only after
verification. Stop helpers, establish identity exclusivity, then activate.

Verify login, WebDAV file contents, quotas, versions/trash and client behavior, then
take a new backup and independently restore representative content. Normal startup
may run `occ upgrade`; therefore select the exact compatible image first. Software
rollback cannot reverse database migrations. Future major upgrades must follow
Nextcloud's supported sequence with a consistent pre-upgrade backup.

## Local upstream adaptation and validation

`services/nextcloud/upstream.nix` moves only the upstream Nextcloud tmpfiles rules
into a storage-gated directory service; it fails evaluation if the expected module
shape changes. This avoids creating state on a missing volume during boot. Remove
it when upstream offers equivalent storage-gated setup. Normal setup is overridden
to forbid automatic installation, secret-bearing bootstrap arguments and deletion
of application trees. Initialization uses the supported `--disable-admin-user`
option, requiring no password transfer. Regression checks cover these boundaries.

CI runs configuration assertions, hook failure injection and a real Nextcloud +
PostgreSQL + encrypted Borg VM restore test with synthetic credentials. Required
operator acceptance remains: unprivileged Proxmox boot, tailnet isolation, iOS/macOS
login/sync, ordinary and chunked 10 GB transfers with checksums, interruption/retry,
quota/full-volume behavior, replacement and fresh-volume recovery. See the
[verification matrix](validation.md); CI is not evidence of a live deployment.

References: [NixOS Nextcloud](https://nixos.org/manual/nixos/stable/#module-services-nextcloud),
[Nextcloud backup](https://docs.nextcloud.com/server/34/admin_manual/maintenance/backup.html),
[restore](https://docs.nextcloud.com/server/34/admin_manual/maintenance/restore.html),
[large uploads](https://docs.nextcloud.com/server/34/admin_manual/configuration_files/big_file_upload_configuration.html),
[Borg verification](https://borgbackup.readthedocs.io/en/1.4.0/usage/check.html).
