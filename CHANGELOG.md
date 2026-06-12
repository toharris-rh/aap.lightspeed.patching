# Changelog

All notable changes to `aap.lightspeed.patching` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (2026-06-12)

- **Native Red Hat Insights → ServiceNow integration documented as-built** —
  `docs/native-servicenow-integration.md`: covers the "Flow Templates for Red
  Hat Insights" ServiceNow app, the per-SE integration-user model, the manual
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
