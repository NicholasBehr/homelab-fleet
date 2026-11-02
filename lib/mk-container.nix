{ nixpkgs, sops-nix }:
{
  deployment,
  variant ? "operational",
  specialArgs ? { },
}:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  inherit specialArgs;
  modules = [
    sops-nix.nixosModules.sops
    deployment
    { homelab.image.variant = variant; }
  ];
}
