# Rehearsal credentials only

immich.yaml contains SOPS-encrypted, uniquely generated disposable rehearsal
Borg credentials. It is not production configuration. The two public recipients
are the rehearsal container and an independent rehearsal recovery identity.
Private keys and passphrases are never committed or passed to CI. Production
requires separate identities, recovery escrow and credentials. Remote backup
remains disabled until an actual repository and verified SSH host keys exist.
