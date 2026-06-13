# Changelog

All notable changes to `aap.lightspeed.patching` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed (2026-06-12)

- **Corrected the native ServiceNow integration to a single fixed user** — the
  "Flow Templates for Red Hat Insights" app authenticates every inbound Hybrid
  Cloud Console call as a hard-coded ServiceNow user `rh_insights_integration`
  (the console wizard has no username field). The earlier per-SE-user model was
  wrong — confirmed by the ServiceNow system log showing repeated
  `Basic authentication failed for user: rh_insights_integration`. Updated
  `docs/native-servicenow-integration.md` and the servicenow skill to document
  one fixed user + one shared secret token, and removed the stray per-SE users.

### Added (2026-06-12)

- **AWS Terraform infrastructure** (`terraform/`) — full VPC stack (VPC, public
  subnet, IGW, route table, security group), RHEL 9 AMI lookup, EC2 instance
  with t-shirt sizing (small/medium/large), SSH key pair injection, S3 remote
  state backend. Ported from the dc1.azure pattern.
- **`playbooks/provision_vm_aws.yml`** — Terraform wrapper playbook: init, apply,
  parse outputs, register the new host in the AAP `lightspeed-patching`
  inventory, publish `set_stats` for downstream workflow nodes, with token
  cleanup and rescue block for ServiceNow incident path.
- **`playbooks/servicenow/update_incident.yml`** — update or resolve a ServiceNow
  incident created by `create_incident.yml`. One playbook drives both the
  "SNow Update Incident" and "SNow Close Incident" JTs via `inc_outcome`
  (`in_progress` / `success` / `failure`). Adapted from dc1.azure
  `update_ritm.yml` for the INC pattern.
- **`ansible.cfg.example`** — Automation Hub configuration template (Red Hat
  Certified + Validated + Community Galaxy). Copy to `~/.ansible.cfg` and fill
  in token.
- **Gateway settings** (`aap_config/files/gateway_settings.yml`) — prelogin
  warning banner and AAP gateway configuration (token expiration, basic auth,
  password policy).
- **Gateway organization** (`aap_config/files/gateway_organizations.yml`) —
  "IT Service Automation" org with Automation Hub certified + validated + Galaxy
  credentials.
- **Automation Hub galaxy credentials** — "Automation Hub - certified" and
  "Automation Hub - validated" credentials in `controller_credentials.yml`,
  reading the offline token from `~/.ansible.cfg`.

### Changed (2026-06-12)

- **CaC load.yml** — wrapped tasks in `block/always` so the token release runs
  even on failure (Ansible requires `always:` inside a `block:`, not at play
  level).
- **Organization** — changed `my_organization` from `"Default"` to
  `"IT Service Automation"` in `aap_config/group_vars/all.yml`.
- **ServiceNow ITSM credential type** — added as a custom credential type in
  `controller_credential_types.yml` (not built in to fresh AAP instances). Uses
  `!unsafe` injector pattern from dc1.azure.
- **Red Hat CDN credential type** — fixed injectors to use `!unsafe` pattern.
- **JT fix** — `SNow Update Incident` now uses `inc_outcome: in_progress`
  (was copy-pasted as `success`).
- **README.md** — fixed stale `ansible.cfg` reference to point to `~/.ansible.cfg`.

- **Native Red Hat Insights → ServiceNow integration documented as-built** —
  `docs/native-servicenow-integration.md`: covers the "Flow Templates for Red
  Hat Insights" ServiceNow app, the single integration-user model, the manual
  steps each SE must take (set the integration-user password in the ServiceNow
  UI, run the console.redhat.com "Add integration" wizard, test), the
  ServiceNow REST endpoint, and the shared-instance (no per-org isolation)
  caveat.
- **`CLAUDE.md`** — repo guidelines + skills index so future Claude sessions
  pick up the conventions and the ServiceNow skill.
- **`.claude/skills/servicenow/SKILL.md`** — ServiceNow integration skill
  (architecture, guardrails, both the EDA and native HCC→ServiceNow paths, and
  the verified instance state).
- **`.gitignore`** — secrets ignore now matches `dev-environment.sh` in any
  directory (still keeps the committed `docs/dev-environment.sh.example`).

### Added

- ServiceNow ITSM integration — change-request lifecycle playbooks
  (create / notice-started / update / incident), CMDB patch-status update, and
  the `snow_log` role for real-time per-host work notes
  (`playbooks/servicenow/`, `playbooks/roles/snow_log/`).
- Event-Driven Ansible rulebook (`rulebooks/lightspeed_events.yml`) that filters
  Red Hat Insights advisory events by severity/type and launches the patch
  workflow.
- AAP Config-as-Code for EDA — event stream, credentials, and rulebook
  activation (`aap_config/`).
- ServiceNow + EDA design docs and setup guides
  (`docs/servicenow-integration.md`, `docs/snow-log.md`, `servicenow/README.md`).
- Community standards — CODE_OF_CONDUCT, CONTRIBUTING, SECURITY, and
  issue / PR templates.
