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
      mkImmich =
        variant:
        mkContainer {
          deployment = ./deployments/immich.nix;
          inherit variant;
          specialArgs.immichNixpkgs = immich-nixpkgs;
        };
      mkHomeAssistant =
        variant:
        mkContainer {
          deployment = ./deployments/home-assistant.nix;
          inherit variant;
        };
      operational = mkImmich "operational";
      bootstrap = mkImmich "bootstrap";
      recovery = mkImmich "recovery";
      homeAssistantOperational = mkHomeAssistant "operational";
      homeAssistantBootstrap = mkHomeAssistant "bootstrap";
      homeAssistantRecovery = mkHomeAssistant "recovery";
      configurations = {
        immich = operational;
        immich-bootstrap = bootstrap;
        immich-recovery = recovery;
        home-assistant = homeAssistantOperational;
        home-assistant-bootstrap = homeAssistantBootstrap;
        home-assistant-recovery = homeAssistantRecovery;
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
          operational
          bootstrap
          recovery
          ;
      };
      fixture = mkContainer {
        deployment = ./tests/fixtures/minimal.nix;
        variant = "bootstrap";
      };
      checks =
        (import ./tests/checks.nix {
          inherit pkgs nixpkgs;
          bootstrap = fixture;
        })
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
          variant = "operational";
        };
        immich-bootstrap = {
          service = "immich";
          variant = "bootstrap";
        };
        immich-recovery = {
          service = "immich";
          variant = "recovery";
        };
        home-assistant = {
          service = "home-assistant";
          variant = "operational";
        };
        home-assistant-bootstrap = {
          service = "home-assistant";
          variant = "bootstrap";
        };
        home-assistant-recovery = {
          service = "home-assistant";
          variant = "recovery";
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
