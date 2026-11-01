{ pkgs, ... }:
let
  c = import ../provision/containers.nix;
in
{
  hardware.graphics = {
    enable = true;
    extraPackages = [
      pkgs.intel-media-driver
      pkgs.vpl-gpu-rt
    ];
  };
  users.groups.render.gid = c.renderGid;
  environment.variables.LIBVA_DRIVER_NAME = "iHD";
}
