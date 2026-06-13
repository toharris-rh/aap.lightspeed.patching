# Changelog

All notable changes to `aap.lightspeed.patching` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (2026-06-13)

- **Nightly teardown** — `playbooks/teardown_vm_aws.yml` unregisters the host
  from the Red Hat CDN **and** Insights (`rhc` state absent), then `terraform
  destroy`s the VM and deregisters it from the AAP inventory. New
  `Lightspeed Patching - Teardown VM (AWS)` JT and two schedules (6 PM + 10 PM
  America/Phoenix, no DST). Idempotent — no VM means a clean no-op.

### Added (2026-06-13)

- **`playbooks/servicenow/register_cmdb_and_relate.yml`** — registers a host in
  the CMDB (`cmdb_ci_linux_server`, create-if-missing) and relates it to the
  **"Lightspeed Patching Demo"** Business Application (`cmdb_ci_business_app`,
  created if absent) via `cmdb_rel_ci` "Uses::Used by". Idempotent. New
  `cmdb_business_app` group var. Dedicated Business App for this demo, distinct
  from the shared "Ansible Demonstrations".

### Fixed (2026-06-13)

- **rhc registration org id is the top-level `rhc_organization` var** (#19
  follow-up) — the `redhat.rhel_system_roles.rhc` role's subscription-manager
  task uses `org_id: "{{ rhc_organization }}"`; it does NOT read the org from
  `rhc_auth` (top level or under `activation_keys`). Both of those gave
  *"org_id is required when using activationkey"*. Set `rhc_organization` in
  `register_rhel.yml`.

- **Provision inventory registration uses `aap_token`** (#19 follow-up) —
  `ansible.controller` 4.8.0 does not accept `controller_oauthtoken` (dc1's
  older pin did); the token param is `aap_token`. Renamed it in the three
  host/group calls in `provision_vm_aws.yml`.

- **Terraform security-group description is ASCII-only** (#19 follow-up) — the
  SG `GroupDescription` contained an em-dash; AWS rejects non-ASCII
  (`InvalidParameterValue ... Character sets beyond ASCII are not supported`),
  failing `terraform apply`. Replaced with a hyphen.

- **Terraform AWS region passed to the provision apply** (#19 follow-up) — the
  AAP AWS credential injects access key/secret but no region, and `providers.tf`
  reads the region from `AWS_DEFAULT_REGION`, so `terraform apply` failed with
  *"invalid AWS Region: "*. `provision_vm_aws.yml` now sets `AWS_DEFAULT_REGION`
  (= `aws_region`, default `us-east-1`) in the apply task environment.

- **Provision VM registers the host via `ansible.controller`** (#19) — `provision_vm_aws.yml`
  used `ansible.platform.host` / `.group`, but `ansible.platform` has **no**
  host/group module, so the job failed with *"couldn't resolve module/action
  'ansible.platform.group'."* Switched to `ansible.controller.host` / `.group`
  (with `controller_host` / `controller_oauthtoken`), matching the dc1.azure
  pattern, and added **`ansible.controller` 4.8.0** to the EE.

### Changed (2026-06-13)

- **Controller project `scm_update_on_launch: true`** (dev-time) — so playbook
  changes merged to `main` take effect on the next job launch without a manual
  project sync. Revisit before production (every workflow node re-syncs).
- **EE bumped to v1.1.0** — added `ansible.controller` 4.8.0 (+collection → minor
  bump per the deliberate-update model). Manifest description and
  `docs/execution-environment.md` updated; `ee_version` default is now the single
  source of truth in `group_vars` (the dev-environment EE-version export is
  commented out). EE build requires `--build-arg PYCMD=/usr/bin/python3.11`
  (a `dnf` bindep pulls Python 3.9, shadowing pip otherwise).

### Added (2026-06-12)

- **Custom terraform-enabled Execution Environment** (#19) — provisioning from
  AAP failed because the provision playbook shells out to the `terraform` CLI,
  absent from every stock EE. New ansible-builder context
  (`execution-environment.yml` + `collections/requirements.yml`) on the
  `ee-minimal-rhel9` base bakes in Terraform 1.15.6 plus certified collections
  (`amazon.aws` 11.3.0, `redhat.rhel_system_roles` 1.120.5, `servicenow.itsm`
  2.15.1, `ansible.platform` 2.7.20260604). Mirrors the dc1.azure pattern:
  immutable semver tags, `microdnf upgrade` hardening, `python3.11-devel`+`wheel`
  for systemd-python.
- **EE published to quay.io → Private Automation Hub → Controller** — new
  `aap_config/files/hub_ee_registries.yml` + `hub_ee_repositories.yml` sync the
  image from `quay.io/zigfreed/lightspeed-patching-ee` into PAH; the
  `Lightspeed Patching - Hub Registry` Container Registry credential lets
  Controller pull it. `controller_execution_environments.yml` now points at the
  PAH copy (`pull: missing`) with a description that enumerates the pinned
  contents. `docs/execution-environment.md` documents build → publish → load.
- **`automation-hub` skill** — talking to Red Hat Automation Hub: certified-vs-
  community preference, resolving certified versions via the Hub API, EE builds.

### Changed (2026-06-12)

- **RHEL registration uses the certified `redhat.rhel_system_roles.rhc` role**
  instead of `community.general.redhat_subscription` (`register_rhel.yml`),
  dropping `community.general` entirely so the stack is all-certified.

### Fixed (2026-06-12)

- **`load.yml` is now idempotent for EDA rulebook activations** (#17) — `extra_vars`
  in `eda_rulebook_activations.yml` was a dict, but the `ansible.eda`
  `rulebook_activation` module declares `extra_vars` as `type: str` and EDA
  stores it as block YAML. The dict coerced to a Python-repr string that never
  matched EDA's stored value, so the module issued a PATCH on every re-run and
  EDA rejected it with *"Activation is not in disabled mode and in stopped
  status."* Re-authored `extra_vars` as a literal YAML string matching EDA's
  representation; re-runs are now a clean no-op (`failed=0`).

### Added (2026-06-12)

- **Automation Analytics / Insights enablement** (#14) — new
  `aap_config/files/controller_settings.yml` (applied via the
  `infra.aap_configuration.controller_settings` role) turns on
  `INSIGHTS_TRACKING_STATE` and sets the console.redhat.com service-account
  `SUBSCRIPTIONS_CLIENT_ID` / `SUBSCRIPTIONS_CLIENT_SECRET`, so the Automation
  Calculator stops reporting *"Missing Gather data for Automation Analytics."*
  Added the `redhat_subscriptions_client_id` / `redhat_subscriptions_client_secret`
  env-var lookups to `group_vars/all.yml` and wired `controller_settings.yml`
  into `load.yml`. Mirrors the working `dc1.azure` pattern.

### Fixed (2026-06-12)

- **EDA rulebook activations attach the Controller credential via `eda_credentials`**
  (#12) — the activations used the key `credentials:`, which the
  `infra.aap_configuration.eda_rulebook_activations` role does not read (it reads
  `eda_credentials`). The RH AAP credential was silently dropped, so EDA rejected
  both activations with *"The rulebook requires a RH AAP credential."* Renamed the
  key to `eda_credentials:`, matching the working `dc1.azure` /
  `aap.eda.dynatrace` reference repos.
- **EDA rulebook activations now reference rulebooks by bare filename** — both
  activations in `aap_config/files/eda_rulebook_activations.yml` used the
  repo-relative path (`rulebooks/servicenow_events.yml`), which EDA rejected as
  *"not found for project."* EDA indexes rulebooks from the project's
  `rulebooks/` directory and references them by filename only, so the prefix was
  dropped (`servicenow_events.yml`, `servicenow_incident_events.yml`). This was
  the last remaining `load.yml` failure.
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
