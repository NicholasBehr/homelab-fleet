#!/usr/bin/env bash
# Hot/bulk placement on two real filesystems inside a disposable mount namespace.
set -euo pipefail
mount --make-rprivate /
workspace=$(mktemp -d)
trap 'umount "$workspace/persist" "$workspace/data" 2>/dev/null || true; rm -rf "$workspace"' EXIT
mkdir "$workspace/persist" "$workspace/data"
mount -t tmpfs tmpfs "$workspace/persist"
mount -t tmpfs tmpfs "$workspace/data"
# Validate the hot/bulk split across actual distinct mounted filesystems.
bash services/immich/layout "$workspace/persist/immich" "$workspace/data/immich" 0 0
printf hot > "$workspace/persist/immich/thumbs/fixture"
printf bulk > "$workspace/persist/immich/upload/fixture"
test "$(stat -c %d "$workspace/persist/immich/thumbs/fixture")" = "$(stat -c %d "$workspace/persist")"
test "$(stat -c %d "$workspace/persist/immich/upload/fixture")" = "$(stat -c %d "$workspace/data")"
test ! -e "$workspace/data/immich/thumbs"
bash services/immich/layout "$workspace/persist/immich" "$workspace/data/immich" 0 0
test "$(cat "$workspace/data/immich/upload/fixture")" = bulk
