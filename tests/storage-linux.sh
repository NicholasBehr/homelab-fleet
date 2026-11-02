#!/usr/bin/env bash
# Run as root inside an isolated mount namespace on a disposable CI runner.
set -euo pipefail
mount --make-rprivate /
workspace=$(mktemp -d)
trap 'umount "$workspace/persist" "$workspace/data" 2>/dev/null || true; rm -rf "$workspace"' EXIT
mkdir "$workspace/persist" "$workspace/data"
guard="$PWD/scripts/verify-storage"
if "$guard" "$workspace/persist" p "$workspace/data" d; then exit 1; fi
mount -t tmpfs tmpfs "$workspace/persist"
mount -t tmpfs tmpfs "$workspace/data"
printf p > "$workspace/persist/.homelab-volume"
printf wrong > "$workspace/data/.homelab-volume"
if "$guard" "$workspace/persist" p "$workspace/data" d; then exit 1; fi
printf d > "$workspace/data/.homelab-volume"
"$guard" "$workspace/persist" p "$workspace/data" d
# Disposable root replacement leaves mounted volumes and their sentinels intact.
printf preserved > "$workspace/persist/state"
mkdir "$workspace/root-old" "$workspace/root-new"
printf discarded > "$workspace/root-old/transient"
rm -r "$workspace/root-old"
test "$(cat "$workspace/persist/state")" = preserved
"$guard" "$workspace/persist" p "$workspace/data" d

