# Immich backup and restoration

The architecture guide defines Immich's hot/bulk placement. This guide is the
service-specific implementation of the generic [disaster restoration
contract](recovery.md#complete-disaster-restoration-contract).

## Backup set

Borg archives `/persist` and `/data/immich` while Immich server/ML, Redis and
Tailscale are stopped. PostgreSQL remains stopped from application writes but is
backed up only through the atomic custom-format `/persist/backup/immich.dump` plus
`versions.json`. Exclude live `/persist/postgresql`, Borg cache, incomplete dump
files and Redis's reproducible backup artifact. Keep services stopped for archive,
verification and retention work; cleanup attempts every restart and retains
recovery intent on failure.

The native schedule is 02:15 Europe/Zurich. Initialize only the approved empty
repository with `borg-job-immich init --encryption=repokey-blake2`; scheduled jobs
never initialize repositories. After activation, run
`systemctl start borgbackup-job-immich`, inspect the current invocation and archive
timestamp, then run `borg-job-immich check --verify-data` at the documented
integrity-check interval.

## Selective restoration

Use the generic recovery sequence with the exact compatible image, PostgreSQL and
extension versions recorded in the archive. Into fresh, marked volumes restore only:

- `persist/immich` and `data/immich`;
- `persist/redis`;
- `persist/backup/immich.dump` and `persist/backup/versions.json`;
- Borg config, authenticated trust, repository endpoint and `persist/secrets`;
- Tailscale identity only after proving the original cannot run.

Preserve the new outer volume markers. Do not restore live PostgreSQL files, Borg
cache or disposable ML models. Verify numeric ownership from the reviewed contract:
Immich1100, PostgreSQL71 and Redis1101. Require all six `.immich` markers and the
`upload`/`library` links into `/data/immich`; thumbnails, previews and encoded video
must remain on `/persist`. Credentials remain root:root mode0600 under mode0700.

With the activation record absent, target inactive, app/ML/Tailscale stopped and
backup timer inactive, start only `immich-directories`, PostgreSQL setup/PostgreSQL
and Redis through the console. Inspect `pg_restore --list`; exclude extension and
public-schema creation entries already owned by NixOS and review the list against
the recorded extension versions. Restore as postgres with:

```sh
pg_restore --single-transaction --exit-on-error --no-owner --no-privileges \
  --role=immich --use-list=REVIEWED_LIST --dbname=immich DUMP
```

This custom-format dump is not Immich's `.sql.gz` UI format. Stop on every error and
never initialize an empty replacement library. Verify database rows/extensions,
original checksums, layout and permissions, then stop all restoration helpers.

After proving identity exclusivity, activate the same root. Verify HTTPS and real
login, asset counts, thumbnails, playback, background jobs, search, CPU inference
and QSV for representative media. Take a new successful backup, run data verification
and independently restore representative database/media content before normal use.
