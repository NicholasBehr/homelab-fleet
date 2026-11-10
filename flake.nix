{
  description = "Disposable unprivileged NixOS LXC service images";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    immich-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      self,
      nixpkgs,
      immich-nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mkContainer = import ./lib/mk-container.nix { inherit nixpkgs; };
      immich = mkContainer {
        deployment = ./deployments/immich.nix;
        specialArgs.immichNixpkgs = immich-nixpkgs;
      };
      homeAssistant = mkContainer {
        deployment = ./deployments/home-assistant.nix;
      };
      configurations = {
        inherit immich;
        home-assistant = homeAssistant;
      };
      mkTemplate =
        host: host.config.system.build.tarball.override { compressCommand = "pixz -t -1 -p 2"; };
      mkCiTemplate =
        host:
        host.config.system.build.tarball.override {
          compressCommand = "cat";
          compressionExtension = "";
          extraInputs = [ ];
        };
      serviceChecks = import ./services/immich/tests/checks.nix {
        inherit
          pkgs
          immich
          ;
      };
      fixture = mkContainer {
        deployment = ./tests/fixtures/minimal.nix;
      };
      checks =
        (import ./tests/checks.nix {
          inherit pkgs nixpkgs fixture;
        })
        // {
          lifecycle = import ./tests/lifecycle.nix { inherit pkgs; };
          lifecycle-wiring = import ./tests/lifecycle-wiring.nix { inherit pkgs configurations; };
        }
        // nixpkgs.lib.mapAttrs' (
          name: value: nixpkgs.lib.nameValuePair ("immich-" + name) value
        ) serviceChecks;
    in
    {
      version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./VERSION);
      deploymentContracts.immich = import ./deployments/immich-contract.nix;
      deploymentContracts.home-assistant = import ./deployments/home-assistant-contract.nix;
      # Explicit catalog: adding a service means registering its outputs here.
      imageCatalog = {
        immich = {
          service = "immich";
          variant = "single";
        };
        home-assistant = {
          service = "home-assistant";
          variant = "single";
        };
      };
      nixosConfigurations = configurations;
      packages.${system} = nixpkgs.lib.mapAttrs (_: mkTemplate) configurations;
      ciImages.${system} = nixpkgs.lib.mapAttrs (_: mkCiTemplate) configurations;
      ciPlan = {
        images = nixpkgs.lib.mapAttrs (_: p: p.drvPath) self.ciImages.${system};
        checks = nixpkgs.lib.mapAttrs (_: c: c.drvPath) checks;
        paths = {
          images = nixpkgs.lib.mapAttrs (_: p: p.outPath) self.ciImages.${system};
          checks = nixpkgs.lib.mapAttrs (_: c: c.outPath) checks;
        };
      };
      checks.${system} = checks;
      devShells.${system}.ci = pkgs.mkShell {
        packages = with pkgs; [
          bash
          nixfmt
          shellcheck
          python3
          jq
          borgbackup
          postgresql_17
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
            bash
            shellcheck
            nixfmt
            python3
            jq
          ];
        };
    };
}
