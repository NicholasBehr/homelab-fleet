# Production ciphertext

immich.yaml contains SOPS-encrypted production Borg credentials. Its public age
recipients belong to the production container and an independent recovery
identity. Private age/SSH keys and passphrases are never committed, embedded in
images, placed in the Nix store or passed to CI. The repository endpoint, verified
SSH host keys, recovery document and live account identifiers remain in protected
operator storage outside this public repository.
