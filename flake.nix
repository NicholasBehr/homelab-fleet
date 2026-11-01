{
  description = "Disposable unprivileged NixOS LXC images";
  inputs = {
    immich-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      immich-nixpkgs,
      sops-nix,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mkHost =
        bootstrap:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit bootstrap; };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/immich.nix
            ({ ... }: {
              disabledModules = [ "services/web-apps/immich.nix" ];
              imports = [ (immich-nixpkgs + "/nixos/modules/services/web-apps/immich.nix") ];
              services.immich.package = (import immich-nixpkgs { inherit system; }).immich;
            })
          ];
        };
      operational = mkHost false;
      bootstrap = mkHost true;
      recovery = operational.extendModules {
        modules = [
          ({ lib, ... }: {
            systemd.services.immich-server.wantedBy = lib.mkForce [ ];
            systemd.services.immich-machine-learning.wantedBy = lib.mkForce [ ];
            systemd.services.tailscale-policy.wantedBy = lib.mkForce [ ];
            homelab.backup.enable = lib.mkForce false;
          })
        ];
      };
    in
    {
      deploymentContract = import ./provision/containers.nix;
      nixosConfigurations = {
        immich = operational;
        immich-bootstrap = bootstrap;
        immich-recovery = recovery;
      };
      packages.${system} = {
        immich = operational.config.system.build.tarball;
        immich-bootstrap = bootstrap.config.system.build.tarball;
        immich-recovery = recovery.config.system.build.tarball;
        default = self.packages.${system}.immich-bootstrap;
      };
      devShells.${system}.ci = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt
          shellcheck
          python3
          borgbackup
          postgresql_17
          age
          sops
          util-linux
        ];
      };
      formatter.${system} = pkgs.nixfmt;
      devShells.aarch64-darwin.default =
        let
          p = import nixpkgs { system = "aarch64-darwin"; };
        in
        p.mkShell {
          packages = with p; [
            age
            sops
            shellcheck
            nixfmt
            python3
          ];
        };
      checks.${system} = {
        bootstrap = bootstrap.config.system.build.toplevel;
        operational = operational.config.system.build.toplevel;
        recovery = recovery.config.system.build.toplevel;
        backup-config =
          (operational.extendModules {
            modules = [
              {
                homelab.backup = {
                  enable = true;
                  repository = "/tmp/disposable-test-repository";
                };
              }
            ];
          }).config.system.build.toplevel;
      };
    };
}
