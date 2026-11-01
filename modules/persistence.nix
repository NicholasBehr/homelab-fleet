{ pkgs, ... }:
let
  c = import ../provision/containers.nix;
in
{
  # Proxmox mounts volumes before init. No in-container mount privileges required.
  systemd.services.storage-contract = {
    description = "Verify persistent storage identities before stateful services";
    wantedBy = [ "multi-user.target" ];
    before = [
      "tailscaled.service"
      "postgresql.service"
      "postgresql-setup.service"
      "immich-server.service"
    ];
    path = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.bash}/bin/bash ${../scripts/verify-storage} /persist /data ${c.persist.marker} ${c.media.marker}
      install -d -m 0700 /persist/secrets /persist/tailscale /persist/backup /persist/borg/config /persist/borg/cache /data/.backup-stage
    '';
  };
  # Machine-id and SSH host keys are intentionally absent from the persistence
  # contract: no ordinary sshd; Tailscale owns the stable network/SSH identity.
  # Root account is declarative and locked; no mutable account database retained.
  systemd.services.tailscaled = {
    requires = [ "storage-contract.service" ];
    after = [ "storage-contract.service" ];
  };
}
