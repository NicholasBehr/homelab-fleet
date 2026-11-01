# Enrollment and recovery identities

The bootstrap image contains no encrypted file and starts without secrets.
Operational image builds also work without ciphertext, but operational-ready
fails with an explicit diagnostic and prevents application/database startup.

Production identity enrollment requires approval. Disposable test identities must
follow the test-resource provenance rules in AGENTS.md; do not introduce production
credentials or retained recovery data into automatically disposable fixtures.
Inside the approved bootstrap console, generate a unique identity once (never
overwrite an existing identity):

```sh
umask 077
test ! -e /persist/secrets/age-key.txt
age-keygen -o /persist/secrets/age-key.txt
age-keygen -y /persist/secrets/age-key.txt
```

Only the public recipient is displayed. Keep the private file in place; do not
copy it through terminal output or Git. On the Mac, create an independent recovery
age identity in an appropriately protected temporary directory, import its private
key into 1Password, and remove the temporary copy after verifying retrieval. Use
1Password's secure document/field import, not shell arguments or command output.
Never commit a private key. Container boot never contacts 1Password.

```sh
nix develop path:.
scripts/secrets-init CONTAINER_PUBLIC_AGE_RECIPIENT RECOVERY_PUBLIC_AGE_RECIPIENT
sops secrets/immich.yaml
```

In the SOPS editor add `borg-passphrase` and `borg-ssh-key` as scalar YAML strings
(the SSH key is a multiline block). Use only actual per-service credentials. Even
if the Storage Box is not yet created, generate and escrow a real service SSH key
and real random Borg passphrase; backups remain disabled until a real repository
and verified known_hosts are configured. Do not create fake credentials to bypass
readiness. Immich uses PostgreSQL peer authentication on its local Unix socket;
no invented database password is required.

Commit only ciphertext and public recipients, then build/release the operational
image from a reviewed commit. Replace bootstrap as in deployment.md; the retained
age key lets sops-nix decrypt into /run/secrets (never /nix/store). Confirm permissions
without printing contents: `stat -c '%a %U %n' /run/secrets/borg-*`.

For recipient changes, first arrange access using an existing authorized identity:
edit .sops.yaml, `sops updatekeys secrets/immich.yaml`, release and replace. A new
container identity requires the recovery key to re-encrypt; verify decryption before
retiring old access. Removing a recipient does not revoke old ciphertext or old
backups: rotate actual Borg passphrase/SSH authorization and consider historic
copies. Rotate Tailscale credentials through the tailnet administration interface.

If both original container and age identity are lost, retrieve the recovery age
identity from 1Password into protected operator storage, decrypt with SOPS locally,
generate a new age key on fresh /persist, update recipients and re-encrypt. Never
pass private values using `sops --set` command arguments. Use its editor or protected
files. Escrow Borg repository URL, passphrase, exported repokey, SSH private key,
verified server host keys, and recovery instructions independently in 1Password.
Restoring Borg must not depend on the backup containing the only recovery key.
