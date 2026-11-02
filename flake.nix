{
  description = "Disposable unprivileged NixOS LXC service images";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    immich-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
      mkContainer = import ./lib/mk-container.nix { inherit nixpkgs sops-nix; };
      mkImmich =
        variant:
        mkContainer {
          deployment = ./deployments/immich.nix;
          inherit variant;
          specialArgs.immichNixpkgs = immich-nixpkgs;
        };
      operational = mkImmich "operational";
      bootstrap = mkImmich "bootstrap";
      recovery = mkImmich "recovery";
      configurations = {
        immich = operational;
        immich-bootstrap = bootstrap;
        immich-recovery = recovery;
      };
      mkTemplate =
        host: host.config.system.build.tarball.override { compressCommand = "pixz -t -1 -p 2"; };
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
      };
      nixosConfigurations = configurations;
      packages.${system} = nixpkgs.lib.mapAttrs (_: mkTemplate) configurations;
      ciPlan = {
        images = nixpkgs.lib.mapAttrs (_: p: p.drvPath) self.packages.${system};
        checks = nixpkgs.lib.mapAttrs (_: c: c.drvPath) checks;
        paths = {
          images = nixpkgs.lib.mapAttrs (_: p: p.outPath) self.packages.${system};
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
            bash
            age
            sops
            shellcheck
            nixfmt
            python3
            jq
          ];
        };
    };
}
