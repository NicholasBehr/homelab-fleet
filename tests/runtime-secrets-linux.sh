#!/usr/bin/env bash
# Root-only metadata checks on fresh disposable runtime files in Linux CI.
set -euo pipefail
workspace=$(mktemp -d /run/homelab-secret-test.XXXXXX)
trap 'rm -rf "$workspace"' EXIT
umask 077
mkdir "$workspace/secrets"
guard="$PWD/scripts/verify-secret"
credential="$workspace/secrets/fixture"
reject() {
  if python3 "$guard" "$credential" >"$workspace/output" 2>&1; then
    echo 'Unsafe runtime credential accepted' >&2; exit 1
  fi
  if grep -q fixture-content "$workspace/output"; then
    echo 'Credential contents leaked' >&2; exit 1
  fi
}
reject
touch "$credential"
reject
printf fixture-content > "$credential"
python3 "$guard" "$credential"
chmod 400 "$credential"
python3 "$guard" "$credential"
chmod 644 "$credential"
reject
chmod 600 "$credential"
chown 1000 "$credential"
reject
chown 0 "$credential"
chmod 755 "$workspace/secrets"
reject
chmod 700 "$workspace/secrets"
mv "$credential" "$workspace/real-secret"
ln -s "$workspace/real-secret" "$credential"
reject
rm "$credential"
mkfifo "$credential"
reject
rm "$credential"
mv "$workspace/real-secret" "$credential"
mv "$workspace/secrets" "$workspace/real-directory"
ln -s "$workspace/real-directory" "$workspace/secrets"
reject
