# Adding a service

Use a simple logical name, e.g. jellyfin. Add explicit role/host imports and an
explicit resource contract; separate application config from Proxmox allocation.
Share Intel media, Tailscale, storage-gate, secrets and Borg modules only where
actually applicable. Refactor the currently Immich-specific backup hooks/Serve
upstream target only when the second service supplies concrete requirements.

Audit state paths, fixed UID/GID assignments and runtime secrets. Give each logical
container its own age identity, Tailscale identity, SSH key and Borg repository.
Use new marker identities and stagger backup schedules below ten simultaneous
connections. Keep CPU ML and media transcoding separate. Extend image, mount failure,
secret, consistent backup/restore and actual LXC replacement checks. No automatic
directory discovery, inventory framework or provisioning script is required.
