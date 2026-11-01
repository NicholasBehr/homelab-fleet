#!/usr/bin/env bash
# Run as root inside an isolated mount namespace on a disposable CI runner.
set -euo pipefail
mount --make-rprivate /
workspace=$(mktemp -d)
trap 'umount "$workspace/persist" "$workspace/data" 2>/dev/null || true; rm -rf "$workspace"' EXIT
mkdir "$workspace/persist" "$workspace/data"
guard="$PWD/scripts/verify-storage"
if "$guard" "$workspace/persist" "$workspace/data" p d; then exit 1; fi
mount -t tmpfs tmpfs "$workspace/persist"
mount -t tmpfs tmpfs "$workspace/data"
printf p > "$workspace/persist/.homelab-volume"
printf wrong > "$workspace/data/.homelab-volume"
if "$guard" "$workspace/persist" "$workspace/data" p d; then exit 1; fi
printf d > "$workspace/data/.homelab-volume"
"$guard" "$workspace/persist" "$workspace/data" p d
# Disposable root replacement leaves mounted volumes and their sentinels intact.
printf preserved > "$workspace/persist/state"
mkdir "$workspace/root-old" "$workspace/root-new"
printf discarded > "$workspace/root-old/transient"
rm -r "$workspace/root-old"
test "$(cat "$workspace/persist/state")" = preserved
"$guard" "$workspace/persist" "$workspace/data" p d

# Validate the hot/bulk split across actual distinct mounted filesystems.
bash scripts/immich-layout "$workspace/persist/immich" "$workspace/data/immich" 0 0
printf hot > "$workspace/persist/immich/thumbs/fixture"
printf bulk > "$workspace/persist/immich/upload/fixture"
test "$(stat -c %d "$workspace/persist/immich/thumbs/fixture")" = "$(stat -c %d "$workspace/persist")"
test "$(stat -c %d "$workspace/persist/immich/upload/fixture")" = "$(stat -c %d "$workspace/data")"
test ! -e "$workspace/data/immich/thumbs"
bash scripts/immich-layout "$workspace/persist/immich" "$workspace/data/immich" 0 0
test "$(cat "$workspace/data/immich/upload/fixture")" = bulk
