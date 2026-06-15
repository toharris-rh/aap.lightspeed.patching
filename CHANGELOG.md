# Changelog

All notable changes to `aap.lightspeed.patching` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (2026-06-15)

- **Phase 11 status summary for team sync** — new `docs/phase11-status.md`:
  human-readable overview of the Automated CVE Remediation pipeline (what we
  built, what we shipped, key discoveries, open gap, remaining slices 4-7,
  and discussion topics for the Eric/Tony planning meeting).

### Changed (2026-06-15)

- **Skills updated with Phase 11 learnings** — the `servicenow`, `lightspeed`,
  and `aap-config` skills now document the CVE incident flow
  (`create_cve_incident.yml`), the Insights notification sweep timing
  discovery, the self-POST workaround, the custom Insights API credential type
  pattern (kind=cloud for JT attachment), the `task_ci` ACL best-effort
  gotcha, remediation plan idempotency, diagnostic API calls, the event stream
  forwarding toggle, project-sync-after-merge, and `set_stats` artifact
  threading between workflow nodes.

- **Talk track build status updated** — `docs/cve-remediation-talk-track.md`
  reflects that Slices 1-3 are merged and validated (was still showing Slices
  3-7 as in-progress).

### Fixed (2026-06-15)

- **`snow_log` role now resolves from `playbooks/servicenow/` (issue #108).**
  `create_cve_incident.yml` includes the `snow_log` role, but it lives at
  `playbooks/roles/snow_log` — out of the playbook-adjacent search path for a
  play under `playbooks/servicenow/`, so the run failed (`role 'snow_log' was
  not found`) before the work notes posted. Added
  `playbooks/servicenow/roles/snow_log` as a symlink to `../../roles/snow_log`
  (the runner already searches `playbooks/servicenow/roles/`), fixing it for
  this and any future ServiceNow playbook.

- **CVE incident no longer fails on the Affected CIs link (issue #106).** The
  `task_ci` (Affected CIs) insert in `create_cve_incident.yml` 403s for REST on
  this instance even though the primary `cmdb_ci` link succeeds; the play died
  there, so the remediation-playbook work note never posted and the workflow
  went red. The `task_ci` link is now best-effort (warn & continue) — the run
  completes green and posts the work notes; the CI is still linked via `cmdb_ci`.

- **`insights_fetch_remediation.yml` is now idempotent (issue #104).** A
  remediation plan name must be unique per org, so a re-run for the same
  CVE+host returned `400 SequelizeUniqueConstraintError` and failed the workflow
  before the incident node ran. The create now tolerates that 400, looks up the
  existing plan by name, and reuses its id (any other 400 still fails loudly) —
  so the CVE→INC demo is repeatable.

- **Insights API creds now reach job templates (issue #101 — real fix for #78).**
  The built-in **Insights** credential is kind `insights`, which the controller
  refuses to attach to a job template (`Cannot assign a Credential of kind
  insights`) — it's only valid on inventories/projects. `load.yml` failed on the
  first such JT, so the CVE rulebook activation + workflow never got created.
  Added a custom **`Lightspeed Patching - Insights API`** credential type (kind
  `cloud`, attachable to JTs) that injects `INSIGHTS_CLIENT_ID` /
  `INSIGHTS_CLIENT_SECRET` / `INSIGHTS_BASE_URL`, plus a `cred_insights_api`
  credential, and repointed the Introduce CVE, Fetch Insights Remediation, and
  SNow Stamp Correlation ID JTs to it. The built-in `Insights` credential remains
  for the future `scm_type: insights` project (Slice 5).

### Added (2026-06-15)

- **Insights CVE rulebook activation + Automated CVE Remediation workflow
  (issue #98, part of #84).** Wires the native Insights→EDA event through to a
  ServiceNow incident:
  - New rulebook **activation** `Lightspeed Patching - Catch Insights CVE Events`
    (`eda_rulebook_activations.yml`) — runs `insights_vulnerability_events.yml`,
    bound to the Insights event stream as `__SOURCE_1`, with the RH AAP
    credential and `my_organization` in `extra_vars`.
  - New **workflow** `Lightspeed Patching - Automated CVE Remediation`
    (`controller_workflow_job_templates.yml`) — minimal two-node path: Fetch
    Insights Remediation → Create CVE Incident (on success).
    `ask_variables_on_launch: true` so the event's `affected_host` +
    `reported_cve` propagate into the nodes. Slices 4–7 (remediation run,
    Standard Change, proof-of-fix) layer onto this workflow later.
  - `Create CVE Incident` JT gains `ask_variables_on_launch: true`;
    `insights_fetch_remediation.yml` now publishes `host_fqdn` via `set_stats`
    so the incident step can resolve the CMDB CI.

### Changed (2026-06-15)

- **CMDB `correlation_id` now holds the Insights *inventory UUID*, not the
  machine-id (issue #94).** `update_cmdb_correlation_id.yml` previously read
  `/etc/insights-client/machine-id` and stored it as `"insights_id: <id>"` —
  the machine-id, which does not match the inventory UUID carried by the native
  Insights→EDA event (`context.inventory_id`). The playbook now resolves the
  host via the Insights inventory API (one call returns both `id` and
  `insights_id`) and sets `correlation_id` = the bare inventory UUID (so an
  incoming event joins directly to the CI) and `comments` = the Insights
  deep-link (`/insights/inventory/<id>`) + the machine-id (preserved). Runs
  entirely on the control node; the correlation JT swaps the Linux Machine
  credential for the Insights credential. (`correlation_display` is read-only via
  the Table API on this instance — a PATCH is silently ignored — so the source is
  named in the comments instead.)

### Fixed (2026-06-15)

- **CVSS in the self-POSTed CVE event was always 0.0.** `introduce_cve.yml` read
  `attributes.cvss_score`, which the Insights vulnerability API does not expose;
  the real field is `cvss3_score` (string, e.g. `"9.100"`), with `cvss2_score` as
  the legacy fallback. The event now carries the true score (e.g. 9.1 for
  CVE-2026-45445).

### Added (2026-06-15)

- **Timely CVE → EDA trigger via self-POST (issue #91).** `introduce_cve.yml`
  now, after the downgrade + `insights-client`, polls the Insights vulnerability
  API for the host's top remediable CVE and POSTs a real-shaped vulnerability
  notification (payload == `rulebooks/insights_vulnerability_events.yml`) straight
  to the event stream (`X-Insight-Token` auth) — so the remediation workflow
  fires in seconds instead of waiting on Red Hat's ~daily, un-triggerable
  vulnerability-notification sweep (observed at 03:30 UTC). The `Forward events to
  rulebook activation` toggle is left manual on purpose.
  - New `INSIGHTS_EDA_EVENT_STREAM_URL` env var (`dev-environment.sh.example`,
    `group_vars/all.yml`); `cred_insights` added to the Introduce CVE JT.
  - `docs/cve-remediation-talk-track.md`: "Triggering a real CVE event into EDA"
    section — the timing finding, reproduction, and the two diagnostic console
    API calls (notification event log + endpoint delivery history).

### Fixed (2026-06-15)

- **ansible-lint `name[template]` violations resolved** — moved Jinja variables
  to the end of task names in `introduce_cve.yml` and
  `update_cmdb_correlation_id.yml` so CI lint passes cleanly.

### Added (2026-06-15)

- **CVE incident with bidirectional CI link (Phase 11 / Slice 3, issue #84).**
  New `playbooks/servicenow/create_cve_incident.yml`: creates a ServiceNow
  Incident when Insights detects a CVE with an automated remediation. Sets
  `cmdb_ci` at creation (not post-hoc) and links the CI via the `task_ci`
  junction table (Affected CIs). Posts the Insights-authored remediation
  playbook YAML as a work note (matching the native integration pattern on
  CTASK0011747) and a summary work note. Publishes `cve_incident_number` /
  `cve_incident_sys_id` for the downstream workflow.
  - New `SNow Create CVE Incident` job template in CaC.

- **Demo talk track + architecture diagram for the auditable CVE remediation
  flow** (issue #84). New `docs/cve-remediation-talk-track.md`: presenter script
  (beat by beat), pre-flight checklist, the GRC/control story (Control01), a
  Mermaid **architecture diagram** that renders on GitHub, and a list of
  screenshots to capture. Documents the Phase 11 evolution of ACT 2.

- **Insights remediation-plan creation (Phase 11 / Slice 2, issue #84).** New
  `playbooks/insights_fetch_remediation.yml`: resolves the host's Insights
  inventory UUID, confirms an automated remediation exists for the CVE
  (`attributes.remediation == 2`), **creates a named Insights remediation plan**
  (`POST /api/remediations/v1/remediations`), and downloads the plan's playbook
  YAML for the ServiceNow audit attachment. A saved plan is what an AAP
  **Insights project** (`scm_type: insights`) syncs and runs natively in Slice 5
  — replacing the reference repo's git-commit/sync glue. Publishes
  `remediation_id` / `has_automated_remediation` / playbook content via
  `set_stats`. Ends cleanly when no automated remediation exists (the Problem
  branch is a future phase).
  - New `Insights` (service-account) credential + `Fetch Insights Remediation`
    job template in CaC. The built-in `Insights` credential type injects
    `INSIGHTS_CLIENT_ID/SECRET` as env vars — **also resolving issue #78**
    (Insights creds into JTs) without a custom credential type.
  - `docs/dev-environment.sh.example`: note that `INSIGHTS_CLIENT_ID/SECRET` may
    reuse the **same service account** as `REDHAT_SUBSCRIPTIONS_CLIENT_ID/SECRET`
    (one SA with the `RHEL administrator` role covers analytics + inventory +
    vulnerability + remediations), and that service accounts are required
    (basic auth is deprecated).

### Added (2026-06-14)

- **Native Red Hat Insights → EDA CVE trigger (Phase 1, slice 1)** — new
  `rulebooks/insights_vulnerability_events.yml` listens for Insights
  vulnerability events (`application == "vulnerability"`, event types
  `new-cve-cvss` / `new-cve-severity` / `new-cve-security-rule` /
  `any-cve-known-exploit`) pushed via the console.redhat.com "Event-Driven
  Ansible" integration, and launches the `Lightspeed Patching - Automated CVE
  Remediation` workflow.
  - New standalone EDA **event stream** `Lightspeed Patching - Insights Event
    Stream` + a `Token Event Stream` credential of the same name
    (`aap_config/files/eda_event_streams.yml`, `eda_credentials.yml`). Creating
    it needs no activation, so `load.yml` provisions it and AAP exposes the
    URL + token to paste into the Insights integration; received events become
    visible there for capturing the real payload. The credential sets
    `http_header_key: X-Insight-Token` — the console.redhat.com "Event-Driven
    Ansible" integration sends the shared token in that header (the certified
    `redhat.insights_eda` plugin's primary header), not `Authorization`; without
    it the event stream rejects the test with "Authorization header is missing".
  - Added `INSIGHTS_EDA_TOKEN` (optional; defaults to `EDA_EVENT_STREAM_TOKEN`)
    to `docs/dev-environment.sh.example`, and the `eda_insights_*` /
    `workflow_cve_remediation_name` names + token binding to `group_vars/all.yml`.
  - The rulebook **activation** and the **workflow object** are wired in later
    slices (they depend on the remediation JTs). The exact payload envelope is
    flagged for live verification in the rulebook header.

- **Patched hosts no longer report stale CVEs — refresh Insights after patching.**
  `patch_rhel.yml` ran `dnf update` but never re-ran `insights-client`, so the
  Insights vulnerability view stayed frozen at the pre-patch snapshot that
  `register_rhel.yml` uploads at registration. A freshly-onboarded, fully-patched
  host therefore showed dozens of phantom CVEs (e.g. openssl CVEs the installed
  package already fixes), drowning any deliberately-introduced demo CVE in stale
  noise. Added a best-effort `insights-client` re-upload after the patch + reboot
  so Insights re-scans the clean, patched state.

### Fixed (2026-06-14)

- **EDA CaC no longer 401s — `load.yml` runs clean end-to-end.** The
  `ansible.platform.token` mint task auto-returns `ansible_facts.aap_token`,
  which Ansible sets as a host fact that overrides the empty `aap_token`
  group_var; the dispatch then used that *Controller* OAuth token as
  `controller_token` for every module. The Controller API accepts it, but the
  EDA API rejects Controller tokens with `401 Unauthorized` — the long-standing
  "EDA is the last failure" (blocked `eda_credentials`, so event streams /
  activations never applied). `aap_token_acquire.yml` now clears `aap_token`
  after minting so the dispatch authenticates with `aap_username` /
  `aap_password` basic auth, which both the Controller and EDA APIs accept.
  `load.yml` now reports `failed=0` and creates the Insights event stream.

- **ASCII-only descriptions on EDA/token CaC objects** so `load.yml` survives
  HTTP clients that encode headers as latin-1 (e.g. Python 3.14's `http.client`,
  which rejects non-ASCII chars with `UnicodeEncodeError`). Replaced em-dashes /
  arrows in the minted CaC token description (`aap_token_acquire.yml`) and the
  three EDA credential descriptions (`eda_credentials.yml`) with ASCII
  equivalents. (Root cause of the load failure is an unsupported interpreter —
  ansible-core 2.18 on Python 3.14 — but ASCII descriptions are correct regardless.)

- **Register CMDB CI no longer fails with a recursive template loop** (issue
  #80). `register_cmdb_and_relate.yml` defined a self-referential play var
  (`cmdb_managed_by: "{{ cmdb_managed_by | default('hercules') }}"`), which
  triggers Ansible's "recursive loop detected in template string" error.
  Renamed the resolved internal variable to `managed_by_user` so the value no
  longer templates itself; `cmdb_managed_by` remains the input (extra var /
  `CMDB_MANAGED_BY`) and the `hercules` default is preserved.

### Changed (2026-06-14)

- **Teardown refactored into a two-step workflow** (issue #81). Splits the
  monolithic `teardown_vm_aws.yml` into two JTs wired by a new
  `Lightspeed Patching - Teardown` workflow:
  1. `Unregister RHEL` — runs against the host inventory, SSHes in and
     unregisters from CDN + Insights (`rhc state: absent`).
  2. `Teardown VM (AWS)` — runs against the control inventory (no host lock),
     does `terraform destroy` + REST host cleanup.
  Eliminates the 409 "Resource is being used by running jobs" race on host
  deletion. Nightly schedules now target the workflow.

### Added (2026-06-14)

- **Consistent hostnames + Insights UUID + Managed-by across Insights / AAP /
  CMDB** (issue #76).
  - `register_rhel.yml` now sets the OS hostname to the public FQDN
    (`inventory_hostname`) as Step 0, before CDN and Insights registration, so
    the host's canonical `fqdn` fact matches the AAP inventory name and the CMDB
    CI name.
  - New `playbooks/servicenow/update_cmdb_correlation_id.yml` stamps the Red Hat
    Insights inventory UUID into the CMDB CI's `correlation_id` field. Reads the
    UUID directly from `/etc/insights-client/machine-id` on the host (via SSH),
    eliminating the need for Insights API credentials. Wired as a new job
    template (`jt_snow_correlation_id`) and a workflow node that runs after
    Register RHEL (parallel to Patch RHEL).
  - `register_cmdb_and_relate.yml` now sets the CI's `managed_by` to a real
    ServiceNow user, resolved from a `user_name` (`CMDB_MANAGED_BY` env var /
    `cmdb_managed_by`, default `hercules`) via a `sys_user` lookup.
  - Added `CMDB_MANAGED_BY` to `docs/dev-environment.sh.example` and
    `cmdb_managed_by` to `aap_config/group_vars/all.yml`.

### Changed (2026-06-14)

- **lightspeed-snow-setup skill — verification + segregation learnings**.
  Added a "Verifying from the ServiceNow side" section (the `syslog_transaction`
  / `sys_log` queries to confirm an inbound POST and its auth, the PDT (UTC−7)
  display-timezone note) and corrected the segregation guidance: a connectivity
  Test persists nothing, and even real incidents (e.g. `INC0011410`) arrive with
  an **empty `Account id:`** field — so SEs cannot be told apart by Red Hat
  org/account ID. Documented the working alternatives (correlate by
  CVE + host + timestamp, or a per-SE assignment group). Fixed the stale claim
  that a Test creates a record.

- **lightspeed skill — clarify the two "Insights UUIDs"**. Documented the
  distinction between the on-host `insights_id`
  (`/etc/insights-client/machine-id`) and the Insights inventory record `id`
  (from the API), how to read the `insights_id` quickly, that it often equals
  the RHSM system identity on EC2, and how to resolve the inventory `id` from it.

### Fixed (2026-06-14)

- **Enable the sshd pre-login banner in `configure_motd.yml`** (issue #67). The
  playbook deployed `/etc/issue.net` but never set sshd's `Banner` directive, so
  with OpenSSH's `Banner none` default the pre-login banner never displayed over
  SSH. Added a `/etc/ssh/sshd_config.d/99-lightspeed-banner.conf` drop-in
  (`Banner /etc/issue.net`, validated with `sshd -t`) and a handler that reloads
  sshd. The post-login `/etc/motd` was unaffected (shown via PAM).

### Added (2026-06-14)

- **Showcase the provisioned-host MOTD in the README** (issue #65). New
  "The provisioned host" section displays the Red Hat Lightspeed CVE Patching
  Engine login banner (`playbooks/files/motd`, installed by
  `playbooks/configure_motd.yml`) in a fenced code block. Docs-only.

### Changed (2026-06-14)

- **Correct contributor docs carried over from the upstream Dynatrace template**
  (issue #63). `CONTRIBUTING.md`, `.github/SECURITY.md`, and
  `.github/pull_request_template.md` described a Dynatrace → AAP EDA (push)
  integration; rewritten for this repo (Lightspeed/AAP/EDA/ServiceNow patching)
  with the correct secret policy (AAP tokens, ServiceNow creds, customer/RHDP
  data). Added `ansible-lint --offline` and the `mock_modules` requirement to the
  CONTRIBUTING workflow, and removed the now-stale CLAUDE.md note about the
  CHANGELOG header still referencing `aap.eda.dynatrace.push`.

### Fixed (2026-06-14)

- **Teardown inventory cleanup 401 — rename `aap_token` fact to `lsp_cac_token`**
  (issue #61). The *Red Hat Ansible Automation Platform* credential type injects
  `aap_token: "{{oauth_token}}"` as an **extra var** (empty when the credential
  carries no OAuth token). Extra vars outrank `set_fact`, so the token minted in
  `aap_token_acquire.yml` was silently shadowed by that empty value and the
  teardown's `Bearer` inventory-lookup calls 401'd ("credentials were not
  provided"). Renamed the internal fact to `lsp_cac_token` in
  `aap_token_acquire.yml`, `teardown_vm_aws.yml`, and `provision_vm_aws.yml`,
  with a comment guarding against reuse of the reserved name. (Previously masked
  by the `//api/` trailing-slash 404 until that was fixed.)

- **Repair the CI lint gate** (issue #58). `ansible-lint --offline` had failed
  on every run since #44 — including on `main` — because
  `servicenow.itsm.configuration_item` was used without a matching entry in
  `.ansible-lint`'s `mock_modules`, tripping the unskippable `syntax-check`
  rule. Added the missing mock so lint passes again. Also documented in the
  repo-workflow skill that `Lint` is not a required status check, so CI must be
  confirmed green (`gh pr checks`) before merging rather than trusting that a
  merge succeeded.

### Added (2026-06-14)

- **Document the `AAP_HOSTNAME` no-trailing-slash requirement** (issue #56).
  `docs/dev-environment.sh.example` and the environment skill now warn that
  `AAP_HOSTNAME` must not end in a slash, because some playbooks (e.g.
  `teardown_vm_aws.yml`) concatenate it raw with `/api/...` and a trailing slash
  yields a `//api/...` URL that the gateway 404s — silently orphaning inventory
  hosts. The skill note also flags the diagnostic trap that the connectivity
  test's `${AAP_HOSTNAME%/}` strips the slash and hides the problem.

### Fixed (2026-06-14)

- **Pin Terraform RHEL AMI lookup to 9.8** (issue #54). `terraform/data.tf`
  used `RHEL-9.*` with `most_recent = true`, which sorts by image creation
  date, not version. Red Hat's regular EUS rebuilds (e.g. 9.4) are often dated
  newer than the latest GA minor, so the lookup silently drifted to 9.4 instead
  of 9.8. Narrowed the name filter to `RHEL-9.8*` so the minor is stable while
  still picking up the newest 9.8 build.

### Changed (2026-06-14)

- **Disable `scm_update_on_launch`** on the Lightspeed Patching project.
  Every workflow node was triggering a redundant project sync (~25s each),
  adding minutes to each workflow run. Sync manually or via `load.yml` after
  pushing changes to `main`.

- **Register CMDB CI — enriched fields, RITM linkage, parallel branch**
  (issue #43). Switched from raw `servicenow.itsm.api` POST to
  `servicenow.itsm.configuration_item` with `state: present` (upsert). CI now
  includes `serial_number` (EC2 instance ID), `model_number` (AWS instance type),
  `environment`, `install_status`, `operational_status`, `category`,
  `assigned_to`, and `assignment_group` — matching dc1.azure field parity. On
  ServiceNow-driven runs, the CI is linked to the originating RITM via the
  `task_ci` (Affected CIs) junction table. The workflow node now runs as a
  parallel branch off Provision VM success (terminal leaf) instead of
  sequentially between Register RHEL and Patch RHEL. CI sys_id published via
  `set_stats` as `cmdb_ci_sys_id`.

- **Provision workflow — RITM callbacks instead of incident callbacks**
  (issue #39). The Provision and Onboard workflow now uses RITM (requested item)
  callbacks matching the dc1.azure pattern: `notice_provision_started.yml` posts
  to the RITM at launch, `update_ritm.yml` closes it on success (state 3) or
  failure (state 4). Incident callbacks (`SNow Update INC`, `SNow Close INC`)
  are removed from the Provision workflow and remain only in the Remediate CVE
  workflow where they belong. All RITM nodes no-op gracefully on manual AAP UI
  launches (no `ticket_number`).

### Changed (2026-06-14)

- **`introduce_cve.yml`** — switched from kernel downgrade (reboot required) to
  userspace package downgrade; defaults to `openssl-1:3.5.5-2.el9_8`. No reboot
  or grubby changes needed. Survey updated: `target_package` + `target_version`
  replace `target_kernel`.

### Added (2026-06-14)

- **`.claude/skills/lightspeed-snow-setup/SKILL.md`** — new Claude skill for
  SEs configuring the native Lightspeed / Insights → ServiceNow integration
  (Flow Templates for Red Hat Insights app, no AAP/EDA): shared-instance model,
  the one fixed integration user, console.redhat.com wizard steps, test/verify,
  and troubleshooting table. Added to skills table in `CLAUDE.md`.

### Changed (2026-06-14)

- **`introduce_cve.yml`** — integrated kernel-downgrade logic directly into the
  playbook (replaces the old stub package-downgrade approach); installs
  `target_kernel` via dnf, sets grubby default, reboots, re-gathers facts, then
  runs `subscription-manager facts --update` and `insights-client`. JT
  `jt_introduce_cve` now points back at `introduce_cve.yml`. Deleted the
  now-redundant `downgrade_kernel.yml`.

- **`jt_introduce_cve`** ("Lightspeed Patching - Introduce CVE (Demo Setup)") —
  switched playbook from `introduce_cve.yml` to `downgrade_kernel.yml`; added
  survey for `target_kernel` (default `5.14.0-427.40.1.el9_4`). Removed the
  now-redundant `jt_downgrade_kernel` JT and its `group_vars` variable.

### Fixed (2026-06-14)

- **`relate_cmdb_to_incident.yml`** — two ansible-lint failures: removed empty
  `vars:` block (schema[playbook]: vars was null); renamed task to move Jinja
  template to end of name string (name[template]).

### Added (2026-06-13)

- **`jt_downgrade_kernel`** ("Lightspeed Patching - Downgrade Kernel") — new JT wrapping
  `playbooks/downgrade_kernel.yml`; installs a target kernel NVR via dnf, sets
  it as the default boot entry with grubby, reboots, then runs
  `subscription-manager facts --update` and `insights-client`. Survey exposes
  `target_kernel` (default `5.14.0-427.40.1.el9_4`). `ask_limit_on_launch`
  enabled so it can target individual hosts.

### Added (2026-06-13)

- **`jt_register_cmdb`** ("Lightspeed Patching - Register CMDB CI") — new JT
  wrapping `register_cmdb_and_relate.yml`; added as a workflow node in
  "Provision and Onboard" between Register RHEL and Patch RHEL. Receives
  `linux_fqdn`, `linux_public_ip`, `linux_instance_id` as workflow artifacts
  from the Provision step. Creates the CI in `cmdb_ci_linux_server` and relates
  it to the "Lightspeed Patching Demo" Business Application.

### Fixed (2026-06-13)

- **`teardown_vm_aws.yml`** — two stale-host bugs fixed:
  1. Host deletion used `ansible.controller.host state: absent` which calls the
     AAP DELETE API and fails with *"Resource is being used by running jobs"*
     when the host is referenced by recent job records. Replaced with a direct
     `ansible.builtin.uri` DELETE loop — the REST endpoint does not carry the
     same lock.
  2. Teardown only removed the host recorded in Terraform state; any stale host
     from a previous run with a different FQDN was left in the inventory.
     Replaced with a query-all-then-delete approach that clears every host in
     the `lightspeed-patching` inventory, not just the current Terraform one.

### Removed (2026-06-13)

- **`jt_register_insights`** job template and its `group_vars` var removed —
  redundant since Insights registration is now part of `register_rhel.yml`.
  The `register_insights.yml` playbook is retained for standalone debugging use.

### Changed (2026-06-13)

- **`register_rhel.yml`** — merged `register_insights.yml` into a single play:
  CDN registration (rhc role) followed immediately by `insights-client --register
  --display-name={{ inventory_hostname }}` + initial check-in. Eliminates one
  workflow node; `register_insights.yml` remains as a standalone playbook/JT for
  targeted re-registration but is no longer in the workflow.
- **"Provision and Onboard" workflow** — removed `register_insights` node; wired
  `patch_rhel` success directly to `snow_update_inc_success`. Combined snow_log
  work note covers both CDN and Insights registration in one message.

### Fixed (2026-06-13)

- **`notice_patch_started.yml`** — hard `assert` on `change_request_sys_id`
  caused the "Provision and Onboard" workflow to fail when no preceding
  `create_change_request` node ran. Replaced with a `when:` guard so the play
  is a no-op (debug message only) when no CHG sys_id is threaded, matching the
  `snow_log` role pattern.

### Added (2026-06-13)

- **`.claude/skills/lightspeed/SKILL.md`** — new Claude skill covering the Red
  Hat Insights / Lightspeed API integration: OAuth2 client_credentials auth,
  Insights inventory + vulnerability endpoints, `--display-name` hostname
  requirement, console.redhat.com RBAC roles, and the CVE→CMDB→incident linking
  pattern. Added to the skills table in `CLAUDE.md`.
- **`playbooks/servicenow/relate_cmdb_to_incident.yml`** — scoped to a single
  provisioned host: exchanges Insights service-account credentials (OAuth2
  `client_credentials`) for a bearer token, looks up the host in the Insights
  inventory to confirm registration and capture the system UUID, resolves the
  host's CI in `cmdb_ci_linux_server`, patches the incident's `cmdb_ci` field,
  and appends a work note with the Insights UUID + CI sys_id. New JT
  **"Lightspeed Patching - SNow Relate CMDB CI to Incident"** with a three-field
  survey (incident number, host FQDN, CVE ID). New `jt_snow_relate_cmdb` var in
  `group_vars/all.yml`; `INSIGHTS_CLIENT_ID` / `INSIGHTS_CLIENT_SECRET`
  (`insights_client_id` / `insights_client_secret`) added to group_vars.

### Added (2026-06-13)

- **CI lint gate** — `.github/workflows/lint.yml` runs `yamllint` +
  `ansible-lint --offline` on PRs and pushes to `main`. `.ansible-lint` config
  (basic profile; skips the intentional patching/CVE-demo patterns, no secrets).
  Fixed the `name[template]` nit in `introduce_cve.yml` and the stale `.yamllint`
  header. Both linters pass clean.
- **First-time-user SSH note** in the environment skill — `~/.ssh/config`
  host-pattern user mappings for manual SSH to provisioned hosts.

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
