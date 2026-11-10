# Production ciphertext

immich.yaml contains SOPS-encrypted production Borg credentials. Its public age
recipients belong to the production container and an independent recovery
identity. Private age/SSH keys and passphrases are never committed, embedded in
images, placed in the Nix store or passed to CI. The repository endpoint, verified
SSH host keys, recovery document and live account identifiers remain in protected
operator storage outside this public repository.

Home Assistant uses a separate SOPS payload and Borg repository when enrolled.
Do not copy Immich credentials or reuse its repository. Keep its age recipient,
backup credentials, endpoint and authenticated host key in the private operator
inventory; only reviewed ciphertext may be added here. Every service follows the
single JSON 1Password Document, independent retrieval and recovery verification
standard in `docs/recovery.md`; ad-hoc Login/Secure Note items and loose key-file
attachments are not the production escrow record.
