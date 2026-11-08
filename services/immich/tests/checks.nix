{
  pkgs,
  operational,
  bootstrap,
  recovery,
}:
let
  backupFixture =
    (operational.extendModules {
      modules = [
        {
          homelab.backup = {
            enable = true;
            repository = "/tmp/disposable-test-repository";
            repositoryFile = pkgs.lib.mkForce null;
          };
        }
      ];
    }).config;
  runtimeFixture =
    (operational.extendModules {
      modules = [
        {
          homelab.backup.repositoryFile = pkgs.lib.mkForce "/tmp/homelab-borg-runtime-repository";
          homelab.backup.prepare = pkgs.lib.mkForce "echo UNEXPECTED_QUIESCE >&2; exit 99";
        }
      ];
    }).config;
  runtimeWrapper = builtins.head (
    builtins.filter (
      p: pkgs.lib.getName p == "borg-job-immich"
    ) runtimeFixture.environment.systemPackages
  );
in
{
  backup-runtime-endpoint = pkgs.runCommand "immich-backup-runtime-endpoint" { } ''
    endpoint=/tmp/homelab-borg-runtime-repository
    test ! -e "$endpoint"
    trap 'rm -f "$endpoint"' EXIT
    if ${runtimeWrapper}/bin/borg-job-immich --version >out 2>err; then
      echo 'Wrapper accepted absent endpoint' >&2; exit 1
    fi
    grep -q 'repository file is missing' err
    # Execute the evaluated native launcher: failure must precede prepare/locking.
    if ${pkgs.bash}/bin/bash ${pkgs.writeText "runtime-backup-launcher" runtimeFixture.systemd.services.borgbackup-job-immich.script} >out 2>err; then
      echo 'Native job accepted absent endpoint' >&2; exit 1
    fi
    grep -q 'repository file is missing' err
    if grep -q UNEXPECTED_QUIESCE err; then exit 1; fi
    printf '%s\n' 'ssh://fixture@example.invalid:23/./archive' > "$endpoint"
    grep -q 'AddressFamily=inet' ${runtimeWrapper}/bin/borg-job-immich
    ${runtimeWrapper}/bin/borg-job-immich --version | grep -q '^borg '
    printf '%s\n' '/tmp/not-a-remote-repository' > "$endpoint"
    if ${runtimeWrapper}/bin/borg-job-immich --version >out 2>err; then
      echo 'Wrapper accepted invalid endpoint' >&2; exit 1
    fi
    grep -q 'exactly one remote SSH repository URI' err
    touch "$out"
  '';
  backup-lifecycle =
    pkgs.runCommand "immich-backup-job-lifecycle"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.bash
          pkgs.coreutils
          pkgs.util-linux
        ];
      }
      ''
        python3 ${./backup-job.py} \
          ${pkgs.writeText "backup-launcher" backupFixture.systemd.services.borgbackup-job-immich.script} \
          ${backupFixture.systemd.services.borgbackup-job-immich.serviceConfig.ExecStopPost} \
          ${../backup-prepare} ${../backup-cleanup}
        touch "$out"
      '';
  ml-cpu = pkgs.runCommand "immich-ml-cpu-policy" { } ''
    mlCheckDir="$TMPDIR/ml-cpu-check"
    mkdir -p "$mlCheckDir"
    cat > "$mlCheckDir/config.py" <<'PY'
    import onnxruntime as ort
    from immich_ml.sessions.ort import _providers_default
    original = ort.get_available_providers
    assert "CPUExecutionProvider" in original()
    for available in (["CPUExecutionProvider"], ["OpenVINOExecutionProvider", "CPUExecutionProvider"],
                      ["CUDAExecutionProvider", "OpenVINOExecutionProvider", "CPUExecutionProvider"]):
        ort.get_available_providers = lambda: available
        assert _providers_default() == ["CPUExecutionProvider"]
    ort.get_available_providers = original
    PY
    grep -q 'MACHINE_LEARNING_CPU_ONLY=1' \
      ${
        operational.config.systemd.units."immich-machine-learning.service".unit
      }/immich-machine-learning.service
    MACHINE_LEARNING_CPU_ONLY=1 \
      GUNICORN_CMD_ARGS="--no-control-socket --check-config --config $mlCheckDir/config.py" \
      ${operational.config.services.immich.package.machine-learning}/bin/machine-learning
    touch "$out"
  '';
  secret-service =
    if builtins.pathExists ../../../secrets/immich.yaml then
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
  bootstrap =
    assert !(bootstrap.config.systemd.services ? immich-server);
    assert !(bootstrap.config.systemd.services ? postgresql);
    bootstrap.config.system.build.toplevel;
  operational = operational.config.system.build.toplevel;
  recovery = recovery.config.system.build.toplevel;
  backup-config = backupFixture.system.build.toplevel;
}
