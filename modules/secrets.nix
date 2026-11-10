{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.homelab.secrets.requiredFiles = lib.mkOption {
    type = lib.types.listOf (lib.types.strMatching "/persist/secrets/[^/]+");
    default = [ ];
    description = "Operator-enrolled root-only runtime credentials; contents never enter image inputs.";
  };
  config.systemd.services.operational-ready = {
    requires = [ "storage-contract.service" ];
    after = [ "storage-contract.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.python3}/bin/python3 ${../scripts/verify-secret} ${lib.escapeShellArgs config.homelab.secrets.requiredFiles}
    '';
  };
}
