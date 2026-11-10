{ nixpkgs }:
{
  deployment,
  specialArgs ? { },
}:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  inherit specialArgs;
  modules = [
    deployment
  ];
}
