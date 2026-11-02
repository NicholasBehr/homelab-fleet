#!/usr/bin/env bash
# Disposable, local encrypted Borg + real PostgreSQL dump/restore test. Non-root.
set -euo pipefail
workspace=$(mktemp -d)
trap 'pg_ctl -D "$workspace/pg" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$workspace"' EXIT
export BORG_REPO="$workspace/repo" BORG_PASSPHRASE='disposable-test-only' BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=no
export BORG_CONFIG_DIR="$workspace/config" BORG_CACHE_DIR="$workspace/cache"
export PGHOST="$workspace" PGPORT=15432
initdb -D "$workspace/pg" -A trust >/dev/null
pg_ctl -D "$workspace/pg" -o "-k $workspace -p $PGPORT -c listen_addresses=''" -w start >/dev/null
createdb original
psql original -c "create table photos(id integer primary key, path text); insert into photos values (1, 'photo.jpg');" >/dev/null
mkdir -p "$workspace/source/persist/immich/thumbs" "$workspace/source/data/immich/upload" "$workspace/source/persist/postgresql"
printf 'representative immutable media bytes' > "$workspace/source/data/immich/upload/photo.jpg"
printf 'generated preview' > "$workspace/source/persist/immich/thumbs/preview.jpg"
printf 'live DB must not be archived' > "$workspace/source/persist/postgresql/live"
ln -s /data/immich/upload "$workspace/source/persist/immich/upload"
mkdir "$workspace/source/persist/backup"
pg_dump -Fc original > "$workspace/source/persist/backup/immich.dump"
borg init --encryption=repokey-blake2
(cd "$workspace/source" && borg create ::fixture persist data/immich --exclude 'pp:persist/postgresql')
borg check --verify-data
mkdir "$workspace/restored"
(cd "$workspace/restored" && borg extract ::fixture)
cmp "$workspace/source/data/immich/upload/photo.jpg" "$workspace/restored/data/immich/upload/photo.jpg"
cmp "$workspace/source/persist/immich/thumbs/preview.jpg" "$workspace/restored/persist/immich/thumbs/preview.jpg"
test "$(readlink "$workspace/restored/persist/immich/upload")" = /data/immich/upload
test ! -e "$workspace/restored/persist/postgresql"
createdb restored
pg_restore --single-transaction --exit-on-error -d restored "$workspace/restored/persist/backup/immich.dump"
test "$(psql restored -Atc 'select path from photos where id=1')" = photo.jpg
# Separate loss/recovery of client state proves repo+passphrase can recover.
rm -rf "$BORG_CONFIG_DIR" "$BORG_CACHE_DIR"
borg list ::fixture >/dev/null
