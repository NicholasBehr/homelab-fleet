{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.homelab.intelMedia.renderGid = lib.mkOption {
    type = lib.types.int;
    default = 303;
  };
  config = {
    hardware.graphics = {
      enable = true;
      extraPackages = [
        pkgs.intel-media-driver
        pkgs.vpl-gpu-rt
      ];
    };
    users.groups.render.gid = config.homelab.intelMedia.renderGid;
    environment.variables.LIBVA_DRIVER_NAME = "iHD";
  };
}
