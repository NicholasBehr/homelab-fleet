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
          };
        }
      ];
    }).config;
in
{
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
