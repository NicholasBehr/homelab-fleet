# Paperless-ngx

Paperless-ngx 3.5.0 is a private, PDF-only document archive in a dedicated
unprivileged NixOS LXC. It binds `127.0.0.1:28981` and is reachable only through
Tailscale Serve. The image uses native Paperless, PostgreSQL 17 and Redis; it has
no Docker daemon, `/data` volume, render device, Tika, Gotenberg, Office/email
conversion or AI integration.

## Proposed resources and storage

The public contract proposes IDs 230/231, four cores, 4096 MiB memory, a 32 GiB
disposable root and a 256 GiB NVMe `/persist` volume. These are capacity estimates,
not allocations or live storage authorization. Check the protected inventory and
prepare the bounded operator plan before provisioning.

| Path | Owner | Restore purpose |
|---|---|---|
| `/persist/paperless/data` | `paperless:paperless` | Tantivy index, classifier state and generated application secret |
| `/persist/paperless/media` | `paperless:paperless` | Original PDFs, generated PDF/A archives and thumbnails |
| `/persist/paperless/consume` | `paperless:paperless` | Pending consumption files |
| `/persist/postgresql/17` | `postgres:postgres` | Live database; never restore from Borg's raw files |
| `/persist/redis` | `redis-paperless:redis-paperless` | Disposable broker state; excluded from Borg |
| `/persist/backup/paperless.dump` | `root:root`, mode 0600 | Logical PostgreSQL restore input |
| `/persist/tailscale` | root/Tailscale | Tailnet identity and Serve state |
| `/persist/secrets/{borg-passphrase,borg-ssh-key}` | `root:root`, mode 0600 | Runtime Borg credentials |
| `/persist/secrets/paperless.env` | `root:root`, mode 0600 | Private HTTPS origin for host, CORS and CSRF validation |

All Paperless paths remain on `/persist`. A later originals-only `/data` split is a
storage-contract migration requiring a fresh consistent backup, exact new-volume
provenance, layout tests, explicit approval and a restoration rehearsal.

## Initialization and activation

Booting the image verifies no application state and starts no workload. Enroll the
dedicated Tailscale identity, Borg repository and `borg-paperless-ngx` recovery
Document while the target remains inactive. After independent escrow and synthetic
restore verification, install `paperless.env` through the protected runtime-file
workflow with exactly one setting and no trailing slash:

```text
PAPERLESS_URL=https://PAPERLESS_HOST.TAILNET.ts.net
```

The value is private operational identity, not an image input. Paperless uses it to
validate the reverse-proxy host, CORS origin and CSRF origin. Then run from an
authenticated root console:

```sh
paperless-initialize
```

The command verifies the exact volume marker, refuses existing documents or
accounts, creates the PostgreSQL schema and prompts for the first administrator
with hidden password entry. It is resumable only when migrations completed but no
account exists. It writes `/persist/paperless/.initialized` after administrator
creation; that persistent marker records application initialization but never
authorizes startup. Activate separately:

```sh
homelab-activate
health-check
```

The disposable root's `/var/lib/homelab/operational-enabled` record is the only
normal startup permission. Activation requires the Paperless marker, application
secret and PostgreSQL cluster, then performs idempotent migrations and a needed-only
Tantivy reindex before starting the scheduler, workers, consumer and web service.

## Backup contract

The daily Borg job takes `/persist/operation.lock`, stops every Paperless writer,
verifies they are inactive, writes an atomic custom-format PostgreSQL dump and
version record, then stops Redis, PostgreSQL and Tailscale. Paperless stays offline
through Borg create, check and retention. Raw PostgreSQL, Redis, Borg cache and a
partial dump are excluded. Cleanup attempts every dependency and application
restart even after one fails and retains restart intent until all succeed.

The service uses one dedicated Storage Box subaccount, repository, SSH key and
passphrase. Store the recovery JSON only as the exact `borg-paperless-ngx` Document
in the `Homelab` vault, tagged `homelab`, following [recovery](recovery.md).

## Fresh-volume restoration

1. Select the exact verified release and archive using the saved version record.
   Create fresh recorded `/persist` storage, initialize only its outer volume
   marker, attach it to an inactive replacement root and retain all source copies.
2. Keep Tailscale, Paperless, Redis and PostgreSQL stopped. Retrieve only
   `borg-paperless-ngx` into protected runtime storage and verify repository access.
3. Extract the allowlisted `persist/paperless` and `persist/backup` paths with
   numeric ownership. Do not extract `persist/postgresql`, `persist/redis`, Borg
   cache or a Tailscale identity while another copy may run.
4. Start only `paperless-directories`, `postgresql-setup`, `redis-paperless` and
   `paperless-secret-key`. Verify the dump is root-owned mode0600 and not readable
   by `postgres`, then feed its already-open stdin into a pristine database:

   ```sh
   runuser -u postgres -- pg_restore \
     --single-transaction --exit-on-error --no-owner --no-privileges \
     --role=paperless --dbname=paperless < /persist/backup/paperless.dump
   ```

5. Verify the application marker, secret-key permissions, database tables, media
   placement and `paperless-manage document_index reindex --if-needed`. Stop every
   helper. Establish Tailscale and application identity exclusivity, then activate.
6. Confirm login, upload and consumption of a representative PDF, OCR text, search,
   thumbnail/PDF viewing, download byte integrity and deletion/trash behavior.
   Run a new Borg backup and independently restore a representative PDF before
   treating the service as protected.

Never restore over running state or move migrated data back to an older Paperless
release. Software rollback requires the matching pre-migration archive restored to
fresh volumes.
