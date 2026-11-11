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
      home-assistant = mkContainer {
        deployment = ./deployments/home-assistant.nix;
      };
      configurations = {
        inherit immich home-assistant;
      };
      contracts = {
        immich = import ./deployments/immich-contract.nix;
        home-assistant = import ./deployments/home-assistant-contract.nix;
      };
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
      mkTemplate =
        host: host.config.system.build.tarball.override { compressCommand = "pixz -t -1 -p 2"; };
      mkCiTemplate =
        host:
        host.config.system.build.tarball.override {
          compressCommand = "cat";
          compressionExtension = "";
          extraInputs = [ ];
        };
      immichChecks = import ./services/immich/tests/checks.nix {
        inherit
          pkgs
          immich
          ;
      };
      homeAssistantChecks = import ./services/home-assistant/tests/checks.nix {
        inherit pkgs home-assistant;
      };
      serviceCheckSets = {
        immich = immichChecks;
        home-assistant = homeAssistantChecks;
      };
      serviceNames = builtins.attrNames configurations;
      validContract =
        name:
        let
          contract = contracts.${name};
        in
        contract ? service
        && contract.service == name
        && contract ? architecture
        && contract.architecture == system
        && contract ? hostname
        && contract ? root
        && contract ? persist
        && contract.persist.path == "/persist"
        && contract ? application
        && builtins.isAttrs contract.application
        && contract ? contractVersion
        && builtins.isInt contract.contractVersion
        && contract.contractVersion > 0;
      validConfiguration =
        name:
        let
          host = configurations.${name}.config;
          contract = contracts.${name};
          versions = builtins.fromJSON host.environment.etc."homelab-versions.json".text;
          requiredHealthUnits = [
            "homelab-operational.target"
            "storage-contract"
            "operational-ready"
            "tailscaled"
          ];
        in
        builtins.hasAttr name versions
        && versions.contractVersion == contract.contractVersion
        && host.homelab.deployment.service == name
        && host.homelab.lifecycle.units != [ ]
        && host.homelab.lifecycle.backupJob == "borgbackup-job-${host.homelab.backup.name}"
        && host.homelab.backup.enable
        &&
          host.homelab.secrets.requiredFiles == [
            host.homelab.backup.passphraseFile
            host.homelab.backup.sshKeyFile
          ]
        && builtins.any (
          volume: volume.path == contract.persist.path && volume.marker == contract.persist.marker
        ) host.homelab.storage.volumes
        && builtins.all (unit: builtins.elem unit host.homelab.health.units) requiredHealthUnits;
      fixture = mkContainer {
        deployment = ./tests/fixtures/minimal.nix;
      };
      prefixedServiceChecks = builtins.foldl' (
        result: name:
        result
        // nixpkgs.lib.mapAttrs' (
          checkName: value: nixpkgs.lib.nameValuePair ("${name}-${checkName}") value
        ) serviceCheckSets.${name}
      ) { } serviceNames;
      checks =
        (import ./tests/checks.nix {
          inherit pkgs nixpkgs fixture;
        })
        // {
          lifecycle = import ./tests/lifecycle.nix { inherit pkgs; };
          lifecycle-wiring = import ./tests/lifecycle-wiring.nix { inherit pkgs configurations; };
        }
        // prefixedServiceChecks;
    in
    assert nixpkgs.lib.assertMsg (
      serviceNames == builtins.attrNames contracts
    ) "Every NixOS configuration must have one same-named deployment contract";
    assert nixpkgs.lib.assertMsg (
      serviceNames == builtins.attrNames imageCatalog
    ) "Every NixOS configuration must have one same-named image catalog entry";
    assert nixpkgs.lib.assertMsg (
      serviceNames == builtins.attrNames serviceCheckSets
    ) "Every NixOS configuration must have one same-named service check set";
    assert nixpkgs.lib.assertMsg (builtins.all (
      name:
      imageCatalog.${name} == {
        service = name;
        variant = "single";
      }
    ) serviceNames) "Image catalog entries must use the service slug and single-image lifecycle";
    assert nixpkgs.lib.assertMsg (builtins.all validContract serviceNames)
      "Deployment contracts must implement the common service contract";
    assert nixpkgs.lib.assertMsg (builtins.all validConfiguration serviceNames)
      "Service configurations must implement versions, lifecycle, backup, secret, storage and health contracts";
    {
      version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./VERSION);
      deploymentContracts = contracts;
      # Explicit catalog: adding a service means registering its output here.
      inherit imageCatalog;
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
