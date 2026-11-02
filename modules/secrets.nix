{ lib, bootstrap, ... }:
let
  encrypted = ../secrets/immich.yaml;
  present = builtins.pathExists encrypted;
in
{
  # The readiness gate orders against the pinned module's actual systemd unit.
  sops.useSystemdActivation = true;
  sops.age = {
    keyFile = "/persist/secrets/age-key.txt";
    generateKey = false;
  };
  sops.secrets = lib.optionalAttrs (!bootstrap && present) {
    borg-passphrase = {
      sopsFile = encrypted;
    };
    borg-ssh-key = {
      sopsFile = encrypted;
    };
  };
  systemd.services.operational-ready = lib.mkIf (!bootstrap) {
    requires = [ "storage-contract.service" ] ++ lib.optional present "sops-install-secrets.service";
    after = [ "storage-contract.service" ] ++ lib.optional present "sops-install-secrets.service";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      test -s /persist/secrets/age-key.txt || { echo "Enroll container age identity first" >&2; exit 1; }
      ${
        if present then
          "test -s /run/secrets/borg-passphrase && test -s /run/secrets/borg-ssh-key"
        else
          "echo 'Operational secrets absent: follow docs/secrets.md' >&2; exit 1"
      }
    '';
  };
}
