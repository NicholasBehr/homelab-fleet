{
  pkgs,
  paperless-ngx,
  paperlessNixpkgs,
}:
let
  c = paperless-ngx.config;
  directoryScript = pkgs.writeText "paperless-directories-script" c.systemd.services.paperless-directories.script;
  schedulerPreStart = pkgs.writeText "paperless-scheduler-prestart" c.systemd.services.paperless-scheduler.preStart;
in
{
  system = c.system.build.toplevel;
  restore = import ./restore.nix { inherit pkgs paperlessNixpkgs; };
  service-config =
    assert c.services.paperless.package.version == "3.5.0";
    assert c.services.paperless.address == "127.0.0.1";
    assert c.services.paperless.port == 28981;
    assert c.services.paperless.dataDir == "/persist/paperless/data";
    assert c.services.paperless.mediaDir == "/persist/paperless/media";
    assert c.services.paperless.consumptionDir == "/persist/paperless/consume";
    assert c.services.paperless.passwordFile == null;
    assert c.services.paperless.database.createLocally;
    assert !c.services.paperless.configureTika;
    assert !c.services.paperless.exporter.enable;
    assert c.services.paperless.settings.PAPERLESS_OCR_LANGUAGE == "deu+eng";
    assert c.services.paperless.settings.PAPERLESS_AI_ENABLED == false;
    assert builtins.elem "/persist/secrets/paperless.env" c.homelab.secrets.requiredFiles;
    assert c.homelab.health.url == "http://localhost:28981/";
    assert c.services.postgresql.dataDir == "/persist/postgresql/17";
    assert c.services.postgresql.enableTCPIP == false;
    assert c.systemd.targets.postgresql.wantedBy == [ ];
    assert c.systemd.tmpfiles.settings."10-paperless" == { };
    assert c.homelab.backup.paths == [ "/persist" ];
    assert !(builtins.elem "/data" c.homelab.backup.paths);
    assert
      c.systemd.targets.homelab-operational.unitConfig.AssertPathExists == [
        "/persist/paperless/.initialized"
        "/persist/paperless/data/nixos-paperless-secret-key.env"
        "/persist/postgresql/17/PG_VERSION"
      ];
    pkgs.runCommand "paperless-ngx-service-config" { } ''
      grep -q 'Refusing symlinked Paperless state directory' ${directoryScript}
      grep -q "to_regclass('public.documents_document')" ${schedulerPreStart}
      grep -q 'document_index reindex --if-needed' ${schedulerPreStart}
      if grep -q 'src-version\|manage_superuser' ${schedulerPreStart}; then exit 1; fi
      grep -q 'ConditionPathExists=/var/lib/homelab/operational-enabled' \
        ${c.systemd.units."paperless-web.service".unit}/paperless-web.service
      grep -q 'Requires=.*operational-ready.service' \
        ${c.systemd.units."paperless-scheduler.service".unit}/paperless-scheduler.service
      grep -q 'EnvironmentFile=/persist/secrets/paperless.env' \
        ${c.systemd.units."paperless-web.service".unit}/paperless-web.service
      touch "$out"
    '';
}
