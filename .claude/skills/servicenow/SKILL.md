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

```
Red Hat Insights/Lightspeed advisory (Security; Critical|Important)
  → Insights webhook (Bearer token)
  → AAP EDA event stream "Lightspeed Patching - Insights Event Stream"
  → rulebook rulebooks/lightspeed_events.yml  (filters severity/type)
  → workflow "Lightspeed Patching - Instantaneous Patch"
      ├── [parallel] playbooks/servicenow/create_change_request.yml   → CHG (New)
      ├── [parallel] playbooks/servicenow/notice_patch_started.yml    → CHG (Implement) + live AAP link
      ├── patch RHEL hosts → snow_log role → real-time work note per host
      ├── [success] update_change_request.yml (Closed) + update_cmdb_patch_status.yml
      └── [failure] create_incident.yml (INC) + update_change_request.yml (Cancelled)
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
| `playbooks/servicenow/create_incident.yml` | Open INC on patch failure |
| `playbooks/roles/snow_log/` | Real-time per-host work notes during patching |

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

## Instance state (verified 2026-06-12)

- The configured `SN_USERNAME` account holds **`admin`** on this shared instance.
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
ServiceNow directly, no AAP). Per-SE setup:

1. **Per-SE integration user** — one ServiceNow user per SE
   (`rh_insights_<handle>`), each granted `x_rhtpp_rh_webhook.rest`, with
   `web_service_access_only=true` and `internal_integration_user=true`. Create
   via REST as admin. Distinct secret per SE → independently rotatable +
   attributable. (A template user `rh_insights_integration` already exists.)
2. **Set the password in the ServiceNow UI** — ⚠️ **`user_password` writes
   over the Table API are silently ignored on this instance** (PATCH returns
   200 but auth still 401). Set each user's password via the user record →
   *Set Password* related link. Ideally the SE sets their own so the secret
   never passes through automation.
3. **Console wizard (manual, per SE)** — in each SE's own `console.redhat.com`
   → Settings → Integrations → Add integration → ServiceNow:
   - Endpoint URL:
     `https://<instance>.service-now.com/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights`
   - Secret token: that SE's integration-user password.
   - Associate event types (advisories/vulnerabilities) in step 3.

⚠️ **No tenant isolation on the shared instance** — every SE's events land in
the same ServiceNow tables. The inbound payload carries the Red Hat org/account
ID; segregate via a custom field / assignment group / filter if needed.

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
