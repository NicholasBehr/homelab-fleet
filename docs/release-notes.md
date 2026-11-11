# v0.4.1 — activation boundary and repository consistency

Prevent upstream Home Assistant and PostgreSQL targets from starting managed
services before the root-local operational activation record exists. Lifecycle
wiring checks now catch enabled targets that can bypass this boundary.

Harmonize Home Assistant with Immich by giving it service-owned backup hooks,
failure-injection tests, evaluated configuration checks and a full system check.
Every service is now required to have a matching deployment, resource contract and
service check set. The example Tailscale policy covers both published services.
Contract application fields use one `application` block consistently; this advances
the Immich contract to version 3 and Home Assistant's to version 2 without changing
paths or ownership values.

Add a normative service-onboarding contract covering names, deployment schema,
versions, lifecycle, backups, restoration, tests, policy and operator acceptance.
Flake evaluation now rejects mismatched configuration, contract, catalog or check
registries and validates each service's common runtime wiring. Shared operations
and recovery guidance is service-neutral, with exact Immich and Home Assistant
restoration procedures in their service guides.

Remove completed credential-migration and multi-image remnants from current code
and documentation. All services use root-only `/persist/secrets` Borg credentials,
one independently verified 1Password recovery Document per service and one image
per service that is inactive by default. No persistent paths, volume markers,
ownership values, application versions or credentials change in this release.

Sanitize live coordinator addressing from public documentation and reject private
IPv4 addresses in docs. Replace roots only after a consistent backup and the usual
identity-exclusivity checks.
