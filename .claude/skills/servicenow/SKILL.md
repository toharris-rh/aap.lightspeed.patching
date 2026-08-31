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

## Incident states

| Integer | State |
|---------|-------|
| 1 | New |
| 2 | In Progress |
| 3 | On Hold |
| 6 | Resolved |
| 7 | Closed |
| 8 | Canceled |

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

## Business Rules & Outbound REST Messages (per-SE scoping)

Each SE creates their own Business Rule + Outbound REST Message pair on the
shared ServiceNow instance. The BR fires when an event happens on a record
related to CIs the SE manages.

### Per-SE scoping via `managed_by` dot-walk

The shared instance hosts ~33 SEs. Instead of filtering by caller/category
(fragile — incidents are created by `service.ansible`, not by the SE), BRs
use a **dot-walk through `cmdb_ci.managed_by`** to scope to the SE's CIs.

`register_cmdb_and_relate.yml` sets `managed_by` on each CI to the SE who
provisioned it (via the `CMDB_MANAGED_BY` env var / `cmdb_managed_by`
playbook var). The BR filter `cmdb_ci.managed_by=<SE sys_id>` ensures only
incidents against that SE's CIs trigger their EDA integration.

### Pattern: named REST message (not inline)

Prefer a **named Outbound REST Message** (`sys_rest_message`) over inline
`RESTMessageV2()` with `setEndpoint()`. The BR script references it by name:
```javascript
var r = new sn_ws.RESTMessageV2('Harris - Lightspeed EDA Event Stream', 'POST');
```
The endpoint URL is configured once on the REST message object. Only the bearer
token comes from a system property (`gs.getProperty('harris.eda_event_stream_token')`).

> **40-char limit** on the `sys_rest_message.name` field — keep names short.

### ⚠️ Updating the EDA URL when the AAP cluster changes (two records, not one)

A named REST message in ServiceNow has **two** `rest_endpoint` fields. The
function-level field **overrides** the parent when set. Updating only the parent
record leaves the BR posting to the old (dead) cluster and returning **HTTP 0**
silently — the BR syslog shows `-> HTTP 0` with no exception, making this hard
to diagnose.

Tony Harris's records (see the Known SE configurations table for names/property):

| Table | sys_id | Field |
|-------|--------|-------|
| `sys_rest_message` | `8e78c6b487e5071064a055383cbb3556` | `rest_endpoint` — parent base URL |
| `sys_rest_message_fn` | `df784e7487e5071064a055383cbb356b` | `rest_endpoint` — **POST function, takes precedence** |
| `sys_properties` | `ce88c6b487e5071064a055383cbb35d9` | `value` — bearer token (`harris.eda_event_stream_token`) |

Update all three when the cluster changes:

```bash
source docs/dev-environment.sh

# 1. Get the new EDA ServiceNow event stream URL from AAP
NEW_URL=$(curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
  "${AAP_HOSTNAME%/}/api/eda/v1/event-streams/1/" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
echo "New URL: $NEW_URL"

# 2. Update parent REST message record
curl -s -u "$SN_USERNAME:$SN_PASSWORD" -X PATCH \
  -H "Content-Type: application/json" \
  -d "{\"rest_endpoint\": \"$NEW_URL\"}" \
  "$SN_HOST/api/now/table/sys_rest_message/8e78c6b487e5071064a055383cbb3556"

# 3. Update POST function record (the one that actually matters)
curl -s -u "$SN_USERNAME:$SN_PASSWORD" -X PATCH \
  -H "Content-Type: application/json" \
  -d "{\"rest_endpoint\": \"$NEW_URL\"}" \
  "$SN_HOST/api/now/table/sys_rest_message_fn/df784e7487e5071064a055383cbb356b"

# 4. Update the bearer token property
curl -s -u "$SN_USERNAME:$SN_PASSWORD" -X PATCH \
  -H "Content-Type: application/json" \
  -d "{\"value\": \"$EDA_EVENT_STREAM_TOKEN\"}" \
  "$SN_HOST/api/now/table/sys_properties/ce88c6b487e5071064a055383cbb35d9"
```

**Verify:** trigger the SNow CVE Demo workflow, then check the BR syslog for
`HTTP 200`:
```bash
source docs/dev-environment.sh
curl -s -u "$SN_USERNAME:$SN_PASSWORD" \
  "$SN_HOST/api/now/table/syslog?sysparm_query=messageLIKEHarris+INC+EDA%5EORDERBYDESCsys_created_on&sysparm_limit=3&sysparm_fields=sys_created_on,message" \
  | python3 -c "import sys,json; [print(r['message']) for r in json.load(sys.stdin).get('result',[])]"
```

**After every `load.yml` — flip test_mode back off** (load.yml resets it to
`true` every run):
```bash
source docs/dev-environment.sh
curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
  -X PATCH "$AAP_HOSTNAME/api/eda/v1/event-streams/1/" \
  -H "Content-Type: application/json" -d '{"test_mode": false}'
```

### Known SE configurations

| SE | Business Rule | REST Message | Token Property | User sys_id |
|----|---------------|--------------|----------------|-------------|
| Eric Ames | `Ames - Service Catalog - dc1.azure` (sc_req_item) | `Ames - DC1.Azure EDA Event Stream` | `dc1.eda_event_stream_token` | `3c2d939d97283110458278671153afb5` |
| Tony Harris | `Harris - Inc` (incident) | `Harris - Lightspeed EDA Event Stream` | `harris.eda_event_stream_token` | `94ac108687ff925064a055383cbb3519` |

Full BR scripts and setup instructions: `servicenow/business-rules.md`.

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

## Instance state (verified 2026-08-31)

- The configured `SN_USERNAME` account holds **`admin`** on this shared instance.
- **CVE→INC→EDA→SNow CVE Remediation pipeline validated end-to-end** (2026-08-31):
  SNow CVE Demo workflow creates INC via `rh_insights_integration`, Business Rule
  fires HTTP 200 to EDA event stream 1, `servicenow_incident_events.yml` rulebook
  launches "SNow CVE Remediation" workflow automatically.
- **Harris - Inc business rule live**: fires after insert on `incident` table,
  scoped to `caller_id.user_name == 'rh_insights_integration'` (not via
  `filter_condition` — see the Critical fields table below). REST message both
  records (`sys_rest_message` + `sys_rest_message_fn`) point to the current AAP
  cluster. Token property `harris.eda_event_stream_token` set to current
  `EDA_EVENT_STREAM_TOKEN`.
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

## Business Rule "Harris - Inc" — as-built wiring (verified 2026-06-15)

The Business Rule fires on **every Insights-created INC insert** and POSTs a
`CVE_INCIDENT` payload to the "Harris - Lightspeed EDA Event Stream", which
the "Catch SNow Incidents" EDA activation then forwards to
`servicenow_incident_events.yml`.

### Critical fields on the Business Rule record (`sys_script`)

| Field | Value | Why it matters |
|---|---|---|
| `collection` | `incident` | **Must be set** — empty = rule never fires |
| `when` | `after` | Runs after the record is committed |
| `action_insert` | `true` | Insert only — don't fire on updates |
| `condition` | `current.caller_id.user_name == 'rh_insights_integration'` | **JavaScript expression**, not query syntax. Scopes to Insights-created INCs only; stops the rule firing on every INC on the shared instance |
| `filter_condition` | `""` (empty) | **Must be cleared** — if left non-empty with a CI reference (e.g. `cmdb_ci.managed_by=...`), the rule silently never fires because the CI is empty on new INCs |
| `active` | `true` | |

Verify via REST:
```bash
source docs/dev-environment.sh
curl -s -u "$SN_USERNAME:$SN_PASSWORD" \
  "$SN_HOST/api/now/table/sys_script/<sys_id>?sysparm_fields=collection,condition,filter_condition,action_insert,active&sysparm_display_value=true"
```

### Payload shape sent to EDA

The Business Rule sends JSON with these top-level fields:

```json
{
  "event": "CVE_INCIDENT",
  "number": "INC0011435",
  "sys_id": "...",
  "state": "New",
  "short_description": "VULNERABILITY: Reported CVE-2026-45445",
  "description": "Account id: ...\nCVSS score: {...full Insights payload JSON...}",
  "category": "...",
  "priority": "5 - Planning",
  "display_name": "ec2-100-31-42-64.compute-1.amazonaws.com"
}
```

`display_name` is extracted by the Business Rule from the embedded JSON blob in
the description field (the Flow Templates app embeds the full Insights payload
under "CVSS score:" in the description; `context.display_name` is the affected
host FQDN). If parsing fails, the field is omitted and a `gs.warn` is logged.

### `servicenow_incident_events.yml` rulebook — Rule 1 (CI-linking)

```yaml
- name: Link CMDB CI to new CVE incident
  condition: event.payload.event == "CVE_INCIDENT" and event.payload.number is defined
  action:
    run_job_template:
      name: "Lightspeed Patching - SNow Relate CMDB CI to Incident"
      organization: "{{ my_organization }}"
      job_args:
        extra_vars:
          incident_number: "{{ event.payload.number }}"
          host_fqdn: "{{ event.payload.display_name | default('') }}"
```

The JT requires `cred_servicenow` **and** `cred_insights_api` — the playbook
queries the Insights inventory API to resolve the host UUID. Missing
`cred_insights_api` causes a silent `no_log` failure on the bearer token task.

### Diagnosing "Business Rule fired but EDA did nothing"

Check in order:
1. **Rule logged?** `GET /api/now/table/syslog?sysparm_query=messageLIKEHarris INC EDA` — zero rows = rule didn't fire (check `collection`, `filter_condition`, `condition`).
2. **Event reached EDA?** AAP → Event Streams → "Harris - Lightspeed EDA Event Stream" — `events_received` count incremented?
3. **Activation in test_mode?** If yes, events are stored but not forwarded — see the aap-config skill.
4. **JT failed?** Check the "SNow Relate CMDB CI to Incident" job log — missing `cred_insights_api` shows as a censored `no_log` failure on the bearer token task.
