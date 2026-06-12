# Changelog

All notable changes to `aap.eda.dynatrace.push` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- **AB#154 — Closed-loop confirmation** — Dynatrace workflow trigger now fires
  on problem close (`onProblemClose: true`). Rulebook split into two rules:
  OPEN events launch the remediation workflow (existing behavior), CLOSED events
  launch the `DC1.Azure - Confirm Resolution (DT)` JT (dc1.azure) to post a
  Dynatrace confirmation work note to the ServiceNow incident — closing the
  detect→remediate→confirm loop.
- Rulebook activation extra_vars gain `confirm_resolution_template` variable.

### Documentation

- Added `docs/INSTALL-UI.md` — full manual install guide using only the AAP and
  Dynatrace web UIs (16 steps across AAP setup, Dynatrace setup, and
  validation/testing). Covers every object to create, field values, process
  group availability alerting, troubleshooting, and event shape reference
  (Phase 5)

### Added (2026-06-09)

- Classic access token (`DT_API_TOKEN`) for Dynatrace Problems API v2 — platform
  tokens (`dt0s16.*`) do not expose `environment-api:problems:*` scopes, so a
  separate `dt0c01.*` token is required. Token name: `dtctl-problems`, scopes:
  `problems.read`, `problems.write`, `securityProblems.read`,
  `securityProblems.write`
- Stale problem cleanup via `POST /api/v2/problems/{id}/close` — closes
  "Process unavailable" problems left behind by decommissioned hosts
- `DT_API_TOKEN` placeholder added to `docs/dev-environment.sh.example`
- Problem management commands documented in `dynatrace/README.md` and install
  skill
- Set `analysisReady: false` on the DT-EDA-PUSH workflow trigger — fires on
  problem open without waiting for Davis root cause analysis, cutting detection
  time from ~6 min to ~2-3 min
- Deleted stale "Hello World" and "Untitled workflow" from Dynatrace (broken
  connectionId and empty eventData respectively)
- OneAgent install playbook cross-references added to `docs/INSTALL.md` and
  `docs/INSTALL-UI.md` prerequisites (links to dc1.azure ADO repo)

### Added

- Initial repo scaffold mirroring dc1.azure conventions
- AAP Config-as-Code: Event Stream, credentials, project, inventory, job templates, rulebook activation
- Dynatrace Config-as-Code: Workflow JSON (`dtctl create workflow`) + EDA connection reference
- Push-model rulebook (`ansible.eda.webhook` source via Event Streams)
- Notify-only playbook (Phase 1 first action)
- Architecture docs, install guide, dev-environment template
- CI: yamllint + secret-leak guard
- dtctl quick-reference and setup docs in `dynatrace/README.md`

### Fixed

- Controller project: added `scm_type: git`, `scm_clean`, `wait: true` — without
  `scm_type` the project created as manual with no SCM URL (#2)
- EDA project: removed unsupported `scm_branch` param (ansible.eda 2.5.0) (#2)

### Added (2026-06-07)

- Process group availability alerting for httpd
  (`dynatrace/process-group-availability.yaml`). Without this rule Dynatrace
  saw httpd stop/start as informational events but never generated a Davis
  problem, so the Workflow trigger never fired and no event reached AAP EDA.
  Schema: `builtin:availability.process-group-alerting`, scope:
  `PROCESS_GROUP-685F2A71A785ADB9` (Apache Web Server httpd), mode:
  `ON_PGI_UNAVAILABILITY`.

### Documented (2026-06-07)

- Captured live Davis problem event shape from job #589/#590
  (`dynatrace/davis-problem-event-shape.yaml`). Key finding: real events use
  dot-notated keys (`event.name`, `event.status`, `host.name`) requiring
  bracket notation in Jinja2, and different field names than the camelCase
  format the triage playbook originally expected.

### Verified (2026-06-05)

- Full push path: direct POST → Event Stream → rulebook match → Notify JT fires (job #205)
- Event payload lands intact in the job log — all fields visible, no data loss
- dtctl v0.28.1 authenticates via browser OAuth, manages Workflows and settings
- Settings schema: `app:dynatrace.redhat.ansible:eda-webhook.connection`
- Default Decision Environment works with Event Streams (no custom DE needed)
