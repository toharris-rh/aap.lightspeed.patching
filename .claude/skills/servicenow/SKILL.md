---
name: servicenow
description: >-
  Work with the aap.lightspeed.patching ServiceNow integration — Change
  Request lifecycle, incident creation, CMDB patch-status updates, real-time
  work notes (snow_log role), and the Insights→EDA→AAP→ServiceNow event flow.
  TRIGGER when the user mentions ServiceNow, SNow, change request / CHG,
  incident / INC, CMDB CI, work note, EDA event stream, Red Hat Insights /
  Lightspeed advisory webhook, or the patch→ITSM callback flow.
  SKIP for pure RHEL patch-play changes that never touch ServiceNow.
---

# ServiceNow Integration — aap.lightspeed.patching

Reference context for the ServiceNow side of this repo. The integration is
event-driven: a Red Hat Insights/Lightspeed advisory triggers an AAP workflow
via EDA, and the workflow calls ServiceNow back at each stage of patching.

## Architecture (read this first)

### Path 1 — Instantaneous Patch (CHG-driven, ServiceNow catalog order)

```
ServiceNow catalog order → EDA event stream → rulebook servicenow_events.yml
  → workflow "Lightspeed Patching - Instantaneous Patch"
      ├── [parallel] playbooks/servicenow/create_change_request.yml   → CHG (New)
      ├── [parallel] playbooks/servicenow/notice_patch_started.yml    → CHG (Implement) + live AAP link
      ├── patch RHEL hosts → snow_log role → real-time work note per host
      ├── [success] update_change_request.yml (Closed) + update_cmdb_patch_status.yml
      ├── [failure] create_incident.yml (INC) + update_change_request.yml (Cancelled)
      └── [either]  update_incident.yml (resolve INC on success / update on failure)
```

### Path 2 — Automated CVE Remediation (INC-driven, Insights→EDA native)

```
Red Hat Insights detects CVE on registered host
  → introduce_cve.yml self-POSTs event (or native Insights ~daily sweep)
  → AAP EDA event stream "Lightspeed Patching - Insights Event Stream"
  → rulebook insights_vulnerability_events.yml  (match application=vulnerability + new-cve-*)
  → workflow "Lightspeed Patching - Automated CVE Remediation"
      ├── insights_fetch_remediation.yml  → Insights UUID → remediation==2 → create plan → download playbook
      │     publishes: has_automated_remediation, remediation_playbook_content, host_fqdn, etc. (set_stats)
      └── [success] create_cve_incident.yml  → INC with cmdb_ci + task_ci + playbook work note
            publishes: cve_incident_number, cve_incident_sys_id (set_stats)
      [Slices 4-7: Standard Change, run remediation, proof-of-fix, close-out — future]
```

Full design doc: `docs/servicenow-integration.md`.
SNow-side setup: `servicenow/README.md`. snow_log role: `docs/snow-log.md`.

## Guardrails

- **Never print `SN_PASSWORD` or `EDA_EVENT_STREAM_TOKEN`** — check by name
  only: `printenv SN_PASSWORD >/dev/null && echo set`. For user-entered
  secrets, suggest `! export VAR=...`.
- **This is a SHARED instance** (~33 other SEs, per dc1.azure). Scope
  every write by `sys_id`, never by name alone. Confirm `SN_HOST` before any
  mutation. Avoid creating/altering global/instance-wide objects without
  explicit confirmation — they affect everyone.
- **Credentials live in `docs/dev-environment.sh`** (gitignored). Use the exact
  `SN_USERNAME` from that file — a plausible-but-wrong username variant returns
  HTTP 401 `User Not Authenticated`, not a clear error. The configured account
  currently holds `admin` on the shared instance.
- **The bearer token is a matched pair** — same value in the AAP EDA
  event-stream credential and the Red Hat Insights webhook Authorization
  header. Generate: `openssl rand -hex 32`. No trailing newline.
- **CHG state integers vary by instance** — validate before relying on them.

## Credentials

| Env var | Purpose |
|---------|---------|
| `SN_HOST` | ServiceNow instance URL (`https://<instance>.service-now.com`) |
| `SN_USERNAME` | API user (needs `itil` + REST; the configured account is admin on this instance) |
| `SN_PASSWORD` | API password |
| `CONTROLLER_HOST` | AAP Controller URL (for live job links in work notes) |
| `EDA_EVENT_STREAM_TOKEN` | Bearer token for Insights→EDA webhook (matched pair) |

All in `docs/dev-environment.sh` (gitignored). Template:
`docs/dev-environment.sh.example`. Load with `source docs/dev-environment.sh`.

## Key files

| File | Purpose |
|------|---------|
| `rulebooks/lightspeed_events.yml` | EDA rulebook — filters advisory severity/type, launches workflow |
| `aap_config/files/eda_event_streams.yml` | EDA event stream definition (CaC) |
| `aap_config/files/eda_rulebook_activations.yml` | Rulebook activation + extra_vars |
| `aap_config/files/eda_credentials.yml` | EDA credentials (CaC) |
| `aap_config/group_vars/all.yml` | Severity filter, CHG/CMDB defaults |
| `playbooks/servicenow/create_change_request.yml` | Create CHG when advisory identified |
| `playbooks/servicenow/notice_patch_started.yml` | CHG → Implement + live AAP link |
| `playbooks/servicenow/update_change_request.yml` | Close CHG (success) / Cancel (failure) |
| `playbooks/servicenow/update_cmdb_patch_status.yml` | Update CI `install_date` (last patched) |
| `playbooks/servicenow/register_cmdb_and_relate.yml` | Create/upsert the `cmdb_ci_linux_server` CI, relate it to the Business App, set `managed_by` (from `cmdb_managed_by` user_name) |
| `playbooks/servicenow/update_cmdb_correlation_id.yml` | Stamp the Insights inventory UUID into the CI's `correlation_id` (after registration) |
| `playbooks/servicenow/create_incident.yml` | Open INC on patch failure |
| `playbooks/servicenow/create_cve_incident.yml` | Open INC for CVE with automated remediation (Phase 11 / Slice 3) |
| `playbooks/servicenow/update_incident.yml` | Update/resolve INC (in_progress / success / failure) |
| `playbooks/roles/snow_log/` | Real-time per-host work notes during patching |
| `rulebooks/insights_vulnerability_events.yml` | EDA rulebook — native Insights CVE events, launches CVE remediation workflow |

## Change Request states

| Integer | State | Set by |
|---------|-------|--------|
| `-1` | New | `create_change_request.yml` |
| `1` | Implement | `notice_patch_started.yml` |
| `3` | Closed | `update_change_request.yml` (success) |
| `4` | Cancelled | `update_change_request.yml` (failure) |

> Integers vary by instance — override via JT extra_vars if needed.

## Module patterns

- **`servicenow.itsm.api`** — generic Table API (POST/PATCH). CHGs, CMDB updates.
- **`servicenow.itsm.api_info`** — read-only query. CI lookups.
- **`servicenow.itsm.incident`** — specialized incident create.

All consume `SN_*` env vars from the `Lightspeed Patching - ServiceNow`
credential (ServiceNow ITSM Credential type) automatically.

## CMDB CI fields (`cmdb_ci_linux_server`)

`register_cmdb_and_relate.yml` upserts the CI via `servicenow.itsm.configuration_item`.
Beyond name/IP/serial it sets two ownership/linking fields:

- **`managed_by`** — a reference to `sys_user`. The playbook resolves
  `cmdb_managed_by` (a ServiceNow **user_name**, from the `CMDB_MANAGED_BY` env
  var, default `hercules`) to a sys_id via a `sys_user` lookup, then passes it in
  the `other:` dict. Unknown user_name → left unset (warns). Known IDs:
  `hercules` (Eric Ames), `toharris` (Tony Harris).
- **`correlation_id`** — the Red Hat Insights **inventory UUID**. Set separately
  by `update_cmdb_correlation_id.yml` *after* Insights registration (the CI is
  created early, before the host exists in Insights), so the CMDB record links
  back to its Insights inventory entry.

## CVE Incident flow (`create_cve_incident.yml`)

Phase 11 / Slice 3 (issue #84, PR #90). Creates a ServiceNow Incident when
Insights detects a CVE with an automated remediation. This is the INC-driven
path (Path 2 above), distinct from the CHG-driven patching flow.

### How it works

1. **Guard:** skips the entire play if `has_automated_remediation != true`
   (consumed from `insights_fetch_remediation.yml` via `set_stats`). The
   Problem-ticket branch (no remediation available) is a future phase.
2. **Resolve CMDB CI:** prefers `cmdb_ci_sys_id` (pre-threaded from the
   provision workflow); falls back to FQDN lookup in `cmdb_ci_linux_server`.
3. **Create incident:** `servicenow.itsm.incident` with `cmdb_ci` set at
   creation (not post-hoc), caller `service.ansible`, impact/urgency medium.
4. **Affected CIs link (best-effort):** attempts a `task_ci` insert for the
   bidirectional Affected CIs relationship. **This 403s on some instances**
   (ACL block on `task_ci` REST insert, issue #106) — the task uses
   `failed_when: false` so it warns and continues. The primary `cmdb_ci` link
   is already set and is sufficient for audit.
5. **Remediation playbook as work note:** posts the raw Insights-authored
   playbook YAML as a structured work note via the `snow_log` role — matching
   the native integration pattern (CTASK0011747 under CHG0030280). A summary
   work note with metadata (CVE, CVSS, host, Insights UUID, remediation plan
   link) follows.
6. **Publish:** `set_stats` publishes `cve_incident_number` and
   `cve_incident_sys_id` for downstream workflow nodes (Slices 4-7).

### Artifact threading via `set_stats`

The Automated CVE Remediation workflow passes data between nodes using
`set_stats` (not extra_vars injection between nodes). The pattern:

- **EDA rulebook** passes `affected_host` + `reported_cve` as workflow
  `extra_vars` (from the event payload).
- **`insights_fetch_remediation.yml`** publishes: `has_automated_remediation`,
  `insights_uuid`, `host_fqdn`, `reported_cve`, `cve_synopsis`,
  `cve_description`, `remediation_id`, `remediation_plan_name`,
  `remediation_playbook_filename`, `remediation_playbook_content`.
- **`create_cve_incident.yml`** consumes all of the above and publishes:
  `cve_incident_number`, `cve_incident_sys_id`.
- The workflow needs `ask_variables_on_launch: true` for the event's vars to
  propagate into the nodes.

### snow_log role path resolution

The `snow_log` role lives at `playbooks/roles/snow_log/`. Playbooks under
`playbooks/servicenow/` search `playbooks/servicenow/roles/` first. A symlink
at `playbooks/servicenow/roles/snow_log → ../../roles/snow_log` (issue #108,
PR #109) makes the role resolve for all ServiceNow playbooks.

## Common tasks

### Verify SNow connectivity (read-only, safe)
```bash
source docs/dev-environment.sh
curl -s -u "$SN_USERNAME:$SN_PASSWORD" -o /dev/null -w "HTTP %{http_code}\n" \
  "$SN_HOST/api/now/table/change_request?sysparm_limit=1&sysparm_fields=number"
# 200 = good; 401 = wrong creds (check username matches SN_USERNAME exactly)
```

### Smoke-test the CHG playbook (creates a real CHG — confirm first)
```bash
source docs/dev-environment.sh
ansible-playbook playbooks/servicenow/create_change_request.yml \
  -e advisory_id="RHSA-2025:TEST" -e advisory_severity="Critical" \
  -e "affected_hosts=host1.example.com,host2.example.com"
```

### Post a work note from the snow_log role
```yaml
- ansible.builtin.include_role:
    name: snow_log
  vars:
    snow_log_message: "Host {{ inventory_hostname }}: patch applied ({{ advisory_id }})."
    # defaults: table=change_request, field=work_notes, ticket from change_request_number/_sys_id
```

### Rotate the bearer token
1. `openssl rand -hex 32`
2. AAP: `Lightspeed Patching - Insights Event Stream` credential → Token → paste
3. Insights: Settings → Integrations → webhook → Authorization header → paste
4. Trigger a test advisory → verify EDA fires

## Instance state (verified 2026-06-15)

- The configured `SN_USERNAME` account holds **`admin`** on this shared instance.
- **CVE→INC pipeline validated:** INC0011424 created end-to-end (Insights→EDA→
  workflow→ServiceNow) with cmdb_ci linked + remediation playbook work note.
  Stray test incidents INC0011422/INC0011423 closed as test artifacts.
- Installed Red Hat scoped apps:
  - **`x_rhtpp_eda` — "Event-Driven Ansible Notification Service" v1.0.6**
    (matches this repo's EDA path).
  - **`x_rhtpp_rh_webhook` — "Flow Templates for Red Hat Insights" v1.0.9**
    (installed 2026-06-12 via the App Repo CI/CD API, since it was already
    downloaded to the instance: `POST /api/sn_cicd/app_repo/install`). This is
    the native HCC→ServiceNow integration app. Roles it provides:
    `x_rhtpp_rh_webhook.rest` (integration/REST) and `x_rhtpp_rh_webhook.support`.
  - Endpoint: `/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights`
    (POST-only; GET returns 405).

## Native HCC→ServiceNow integration — as-built / how-to

The chosen integration on this instance is the **native** path (Insights →
ServiceNow directly, no AAP).

⚠️ **ONE fixed integration user, ONE shared secret.** The app authenticates
**every** inbound HCC call as the hard-coded ServiceNow user
**`rh_insights_integration`**. That's why the console wizard asks only for a
*Secret token* and no username — the Secret token is just that user's password.
**You cannot do per-SE users or per-SE secrets with this app**; all SEs share
the same endpoint and the same secret token. (An earlier version of this skill
wrongly described a per-SE-user model — that was corrected after the system log
showed `Basic authentication failed for user: rh_insights_integration`.)

Setup:

1. **One integration user `rh_insights_integration`** — granted
   `x_rhtpp_rh_webhook.rest`, with `web_service_access_only=true` and
   `internal_integration_user=true`. Create via REST as admin. **Never delete
   it** — it's the account the app requires.
2. **Set its password in the ServiceNow UI** — ⚠️ **`user_password` writes over
   the Table API are silently ignored on this instance** (PATCH returns 200 but
   auth still 401). Set it via the user record → *Set Password* related link.
   This password is the shared Secret token; distribute it to SEs securely.
3. **Console wizard (manual, per SE, same values for all)** — each SE in their
   own `console.redhat.com` → Settings → Integrations → Add integration →
   ServiceNow:
   - Endpoint URL:
     `https://<instance>.service-now.com/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights`
   - Secret token: the `rh_insights_integration` password from step 2.
   - Associate event types (advisories/vulnerabilities).

⚠️ **No tenant isolation on the shared instance** — all SEs authenticate as the
same user, so every SE's events land in the same ServiceNow tables. The inbound
payload carries the Red Hat org/account ID; segregate via a custom field /
assignment group / filter if needed.

Full runbook: `docs/native-servicenow-integration.md`.

## Two integration paths — don't confuse them

1. **This repo (EDA path)** — Insights webhook → AAP EDA event stream →
   ServiceNow via playbooks above. The HCC integration is a **Webhook** type
   (Secret token = the EDA bearer token) pointing at the AAP EDA event stream
   URL. ServiceNow is written by AAP, not by the console.
2. **Native HCC→ServiceNow** — uses the "Flow Templates for Red Hat Insights"
   store app; the HCC "ServiceNow" integration's Secret token is the
   *password of the `rh_insights_integration` ServiceNow user*, and the
   Endpoint URL is
   `https://<instance>.service-now.com/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights`.
   Bypasses AAP/EDA entirely. Store app install + console wizard are both
   manual UI steps.
