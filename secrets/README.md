# Runtime credentials

This directory contains documentation only. Production credential payloads,
including ciphertext, do not belong in Git, images, the Nix store or CI.

Each service has independently enrolled root-only files at
`/persist/secrets/{borg-passphrase,borg-ssh-key}`. Both are included in encrypted
Borg backups. One complete 1Password Borg recovery Document per service provides
independent access after loss of `/persist`; see `docs/recovery.md` for its schema,
permissions, retrieval checks and migration procedure. The resettable Storage Box
password is enrollment-only and omitted from escrow.

Historical releases used SOPS. Preserve their age identities and recovery records
until replacement and restoration are proven; removing ciphertext from the current
tree does not remove it from Git history or old releases.
