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
mkdir -p "$workspace/source/media"
printf 'representative immutable media bytes' > "$workspace/source/media/photo.jpg"
pg_dump -Fc original > "$workspace/source/database.dump"
borg init --encryption=repokey-blake2
(cd "$workspace/source" && borg create ::fixture .)
borg check --verify-data
mkdir "$workspace/restored"
(cd "$workspace/restored" && borg extract ::fixture)
cmp "$workspace/source/media/photo.jpg" "$workspace/restored/media/photo.jpg"
createdb restored
pg_restore -d restored "$workspace/restored/database.dump"
test "$(psql restored -Atc 'select path from photos where id=1')" = photo.jpg
# Separate loss/recovery of client state proves repo+passphrase can recover.
rm -rf "$BORG_CONFIG_DIR" "$BORG_CACHE_DIR"
borg list ::fixture >/dev/null
