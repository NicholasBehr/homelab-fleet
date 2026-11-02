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
      immichPkgs = import immich-nixpkgs { inherit system; };
      cpuMachineLearning = immichPkgs.immich-machine-learning.overrideAttrs (old: {
        pname = "immich-machine-learning-cpu";
        patches = (old.patches or [ ]) ++ [ ./patches/immich-ml-cpu-only.patch ];
      });
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
              services.immich.package = immichPkgs.immich.override {
                immich-machine-learning = cpuMachineLearning;
              };
            })
          ];
        };
      # Keep xz templates compatible with Proxmox, but bound compressor CPU/memory.
      # The upstream pixz default is expensive when several images build together.
      mkTemplate =
        host:
        host.config.system.build.tarball.override {
          compressCommand = "pixz -t -1 -p 2";
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
        immich = mkTemplate operational;
        immich-bootstrap = mkTemplate bootstrap;
        immich-recovery = mkTemplate recovery;
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
        ml-cpu = pkgs.runCommand "immich-ml-cpu-policy" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          policy=$(find ${operational.config.services.immich.package.machine-learning}/lib \
            -path '*/immich_ml/models/constants.py' -type f)
          python3 - "$policy" <<'PY'
          import ast, pathlib, sys
          tree = ast.parse(pathlib.Path(sys.argv[1]).read_text())
          providers = [n.value for n in tree.body if isinstance(n, ast.Assign)
                       and any(isinstance(t, ast.Name) and t.id == "SUPPORTED_PROVIDERS" for t in n.targets)]
          assert len(providers) == 1
          assert ast.literal_eval(providers[0]) == ["CPUExecutionProvider"]
          PY
          GUNICORN_CMD_ARGS='--no-control-socket --check-config' \
            ${operational.config.services.immich.package.machine-learning}/bin/machine-learning
          touch "$out"
        '';
        secret-service =
          if builtins.pathExists ./secrets/immich.yaml then
            pkgs.runCommand "operational-secret-service-wiring" { } ''
              test -s ${
                operational.config.systemd.units."sops-install-secrets.service".unit
              }/sops-install-secrets.service
              grep -q 'Requires=.*sops-install-secrets.service' \
                ${operational.config.systemd.units."operational-ready.service".unit}/operational-ready.service
              grep -q 'After=.*sops-install-secrets.service' \
                ${operational.config.systemd.units."operational-ready.service".unit}/operational-ready.service
              test -s ${
                recovery.config.systemd.units."sops-install-secrets.service".unit
              }/sops-install-secrets.service
              touch "$out"
            ''
          else
            pkgs.runCommand "no-enrolled-secret-service" { } ''touch "$out"'';
        # Exercise all matching tmpfiles z rules: they accumulate, rather than
        # selecting only the first file's rule for a path.
        tun-permissions =
          pkgs.runCommand "container-tun-permissions" { nativeBuildInputs = [ pkgs.systemd ]; }
            ''
              mkdir -p root/etc/tmpfiles.d root/dev/net
              printf 'root:x:%s:%s::/:/bin/sh\n' "$(id -u)" "$(id -g)" > root/etc/passwd
              printf 'root:x:%s:\n' "$(id -g)" > root/etc/group
              cp ${bootstrap.config.environment.etc."tmpfiles.d/static-nodes-permissions.conf".source} \
                root/etc/tmpfiles.d/static-nodes-permissions.conf
              cat > root/etc/tmpfiles.d/00-nixos.conf <<'RULES'
              ${nixpkgs.lib.concatStringsSep "\n" bootstrap.config.systemd.tmpfiles.rules}
              RULES
              touch root/dev/net/tun
              chmod 0666 root/dev/net/tun
              systemd-tmpfiles --root="$PWD/root" --create --prefix=/dev/net/tun
              test "$(stat -c '%a' root/dev/net/tun)" = 600
              touch "$out"
            '';
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
