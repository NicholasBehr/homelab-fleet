{ immichNixpkgs, system }:
let
  pkgs = import immichNixpkgs { inherit system; };
  cpu = pkgs.immich-machine-learning.overrideAttrs (old: {
    pname = "immich-machine-learning-cpu";
    patches = (old.patches or [ ]) ++ [ ./patches/immich-ml-cpu-only.patch ];
  });
in
pkgs.immich.override { immich-machine-learning = cpu; }
