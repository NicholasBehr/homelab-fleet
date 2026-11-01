#!/usr/bin/env bash
set -euo pipefail
workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
umask 077
age-keygen -o "$workspace/container.key" 2>/dev/null
age-keygen -o "$workspace/recovery.key" 2>/dev/null
container=$(age-keygen -y "$workspace/container.key")
recovery=$(age-keygen -y "$workspace/recovery.key")
printf 'fixture: disposable-test-value\n' > "$workspace/plain.yaml"
sops --config /dev/null --encrypt --age "$container,$recovery" "$workspace/plain.yaml" > "$workspace/encrypted.yaml"
for identity in container recovery; do
  SOPS_AGE_KEY_FILE="$workspace/$identity.key" sops --decrypt "$workspace/encrypted.yaml" > "$workspace/decrypted.yaml"
  cmp "$workspace/plain.yaml" "$workspace/decrypted.yaml"
done
