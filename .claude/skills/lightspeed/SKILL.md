---
name: lightspeed
description: >-
  Red Hat Insights / Lightspeed API integration for aap.lightspeed.patching —
  OAuth2 service-account auth, Insights inventory and vulnerability API calls,
  the CVE→Insights→CMDB→incident linking pattern, insights-client hostname
  requirements, and the console.redhat.com RBAC roles needed. TRIGGER when the
  user mentions Insights API, console.redhat.com API calls, Insights inventory,
  Insights UUID, CVE lookup, vulnerability API, insights-client, display-name,
  service account roles on HCC, the relate_cmdb_to_incident playbook, the
  remediations API / remediation plans, the AAP Insights credential type, or the
  Insights project mount (scm_type insights).
  SKIP for pure EDA/rulebook wiring (use aap-config) and pure ServiceNow ITSM
  logic (use servicenow).
---

# Red Hat Insights / Lightspeed API — aap.lightspeed.patching

Reference for all direct API calls to `console.redhat.com` — auth, endpoints,
RBAC, and the playbook that links Insights data to ServiceNow.

## Authentication — OAuth2 client_credentials

All Insights API calls use a **service account** (client ID + secret) exchanged
for a short-lived bearer token via Red Hat SSO:

```
POST https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded
Body: grant_type=client_credentials&client_id=<id>&client_secret=<secret>
```

Response: `{"access_token": "...", "expires_in": 900, ...}`

**In playbooks** (see `relate_cmdb_to_incident.yml`):
```yaml
- name: Obtain Insights bearer token
  ansible.builtin.uri:
    url: "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
    method: POST
    body_format: form-urlencoded
    body:
      grant_type: client_credentials
      client_id: "{{ lookup('ansible.builtin.env', 'INSIGHTS_CLIENT_ID') }}"
      client_secret: "{{ lookup('ansible.builtin.env', 'INSIGHTS_CLIENT_SECRET') }}"
    status_code: 200
  register: insights_token_resp
  no_log: true
```

## Env vars

| Var | Purpose |
|-----|---------|
| `INSIGHTS_BASE_URL` | Base URL (default `https://console.redhat.com`) |
| `INSIGHTS_CLIENT_ID` | Service account client ID |
| `INSIGHTS_CLIENT_SECRET` | Service account client secret |

These are currently set to the **same credentials** as
`REDHAT_SUBSCRIPTIONS_CLIENT_ID` / `REDHAT_SUBSCRIPTIONS_CLIENT_SECRET` — one
service account serves both Automation Analytics uploads and direct Insights API
calls. Group vars bindings: `insights_client_id`, `insights_client_secret`,
`insights_base_url` in `aap_config/group_vars/all.yml`.

## console.redhat.com RBAC roles required

Service accounts cannot be added to the default access group. Create a **custom
User Access group** (Settings → User Access → Groups) and assign:

| Role | Permission | Why |
|------|-----------|-----|
| **Inventory Hosts Viewer** | `inventory:hosts:read` | Look up registered hosts by display_name |
| **Vulnerability Viewer** | `vulnerability:*:read` | Query CVEs affecting a system |
| **Remediations user** (or administrator) | `remediations:*:*` | Create remediation plans + let an AAP Insights project sync them |

Add the service account to the group on the **Service Accounts** tab.

> **Basic auth is deprecated** for the HCC / Lightspeed APIs — use a **service
> account** (client_id/secret → bearer token), not portal username/password.
> Verify a service account's reach quickly: exchange the token, then
> `curl -o /dev/null -w "%{http_code}"` against the inventory / vulnerability /
> remediations endpoints (200 = the role is present, 403 = missing).

### ⚠️ `remediations:remediation:write` — common 403 (verified 2026-06-16)

`insights_fetch_remediation.yml` calls `POST /api/remediations/v1/remediations`
to create the remediation plan. This fails with **HTTP 403** if the service
account only has **Remediations viewer** (read-only). The group must include
**Remediations user** (or higher), which grants `remediations:remediation:write`.

Symptom in AAP: the Fetch Insights Remediation JT fails at
"Create the Insights remediation plan (tolerate already-exists)" with:

```
"Permission remediations:remediation:write is required for this operation"
```

Fix: in console.redhat.com → Settings → User Access → your group → Roles,
replace **Remediations viewer** with **Remediations user** (or add it). Verify:

```bash
source docs/dev-environment.sh
TOKEN=$(curl -s -X POST "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=${INSIGHTS_CLIENT_ID}" \
  -d "client_secret=${INSIGHTS_CLIENT_SECRET}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://console.redhat.com/api/rbac/v1/access/?application=remediations" \
  | python3 -c "import json,sys; [print(r['permission']) for r in json.load(sys.stdin)['data']]"
# Must show: remediations:remediation:write
```

## Insights API endpoints used

### Inventory — look up a host by display_name

```
GET https://console.redhat.com/api/inventory/v1/hosts?display_name=<fqdn>
Authorization: Bearer <access_token>
```

Response: `{"total": 1, "results": [{"id": "<uuid>", "display_name": "...", ...}]}`

- `results[0].id` is the **Insights system UUID** used in all other API calls.
- Returns `total: 0` if the host is not registered — run "Register Insights" JT first.

### Two different "Insights UUIDs" — don't confuse them

There are two UUIDs and they answer different questions:

| UUID | Where | What it is |
|------|-------|-----------|
| **`insights_id`** (machine-id) | on the host: `sudo cat /etc/insights-client/machine-id` | The client's own identity, written at registration. Also exposed as `insights_id` on the inventory record. |
| **inventory record `id`** | API: `results[0].id` from the inventory lookup above | The Insights **inventory** UUID; this is the one the vulnerability/system endpoints take in their path. |

When someone asks for "the Insights UUID" of a provisioned host, the quickest answer is the on-host `insights_id`:

```bash
sudo cat /etc/insights-client/machine-id    # e.g. 1ad8a893-4c28-44d9-87f0-c3a91570fc83
sudo insights-client --status               # confirms registration ("Insights API confirms registration")
```

Notes:
- On EC2 RHEL the `insights_id` often **equals the RHSM system identity**
  (`sudo subscription-manager identity`) — they were the same value on the
  provisioned demo host, which can be mistaken for a coincidence but is normal.
- If you specifically need the inventory record `id` (the one API calls take),
  resolve it from the `insights_id` or the host FQDN via the inventory lookup —
  `GET /api/inventory/v1/hosts?insights_id=<machine-id>` or `?display_name=<fqdn>`.

### Vulnerability — CVEs affecting a specific system

```
GET https://console.redhat.com/api/vulnerability/v1/systems/<uuid>/cves
Authorization: Bearer <access_token>
```

Optional query params:
- `?cve_name=CVE-2025-38352` — filter to a specific CVE
- `?remediation=2` — only CVEs with an Ansible remediation playbook available

The per-CVE record carries `attributes.remediation` — **`2` means an Ansible
remediation playbook is available** (the "automated solution exists" signal that
drives the Standard-Change-vs-Problem branch).

### Remediations — create a named plan + download its playbook

A **named remediation plan** (not the ephemeral `/playbook` generator) is what an
AAP Insights project syncs and runs. Create one, then download its playbook YAML
for an audit attachment:

```
POST https://console.redhat.com/api/remediations/v1/remediations
Authorization: Bearer <token>      Content-Type: application/json
```
Body (confirmed against the live `RemediationInput` OpenAPI schema):
```json
{
  "name": "<plan name, no leading/trailing whitespace>",
  "auto_reboot": true,
  "add": { "issues": [ { "id": "vulnerabilities:<CVE>", "systems": ["<inventory-uuid>"] } ] }
}
```
- `issue.id` pattern: `(advisor|vulnerabilities|ssg|test|patch-advisory|patch-package):...`
- Returns `{ "id": "<remediation-uuid>", ... }`. A plan can only be created when a
  pre-built playbook exists (i.e. `remediation == 2`).
- Download the playbook: `GET /api/remediations/v1/remediations/<id>/playbook`
  with `Accept: text/vnd.yaml`.
- The full spec is self-describing: `GET /api/remediations/v1/openapi.json`.

Implemented in `playbooks/insights_fetch_remediation.yml` (Phase 11 / Slice 2).

### Running remediations from AAP — the native Insights mount (no git glue)

AAP has built-in Insights integration — **prefer this over committing generated
YAML to a git project**:

- **`Insights` credential type** (kind: `insights`) — accepts a **service account**
  (`client_id`/`client_secret`) or basic auth. Its injectors set env vars
  `INSIGHTS_CLIENT_ID` / `INSIGHTS_CLIENT_SECRET` (and `INSIGHTS_USER/PASSWORD`),
  so attaching it to a JT feeds any Insights-API playbook its creds — **this is
  the resolution to issue #78**. CaC: `cred_insights` in
  `aap_config/files/controller_credentials.yml`.
- **`scm_type: insights` project** — syncs the account's saved remediation plans
  as runnable playbooks; a JT then runs the plan against the inventory. This is
  Slice 5 of Phase 11 (issue #84).

## Hostname requirement — always use the public FQDN

**Always pass `--display-name={{ inventory_hostname }}` when registering with
`insights-client`.** The EC2 OS hostname is the private DNS name
(`ip-10-50-0-x.ec2.internal`); without `--display-name`, Insights registers
under the private name, which won't match the AAP inventory hostname or the
CMDB CI name.

`playbooks/register_insights.yml` already implements this:
```yaml
- name: Register with Insights (display-name set to public FQDN)
  ansible.builtin.command:
    cmd: "insights-client --register --display-name={{ inventory_hostname }}"
```

**Any new task that calls `insights-client` must include `--display-name={{ inventory_hostname }}`.**

## CVE → CMDB → Incident linking pattern

`playbooks/servicenow/relate_cmdb_to_incident.yml` — scoped to a single
provisioned host:

1. Exchange service-account creds → Insights bearer token
2. `GET /api/inventory/v1/hosts?display_name=<host_fqdn>` → Insights UUID
3. `servicenow.itsm.api_info` on `cmdb_ci_linux_server` by FQDN → CI sys_id
4. `servicenow.itsm.api` PATCH incident `cmdb_ci` field → links the CI
5. Append work note with Insights UUID + CI details

**Inputs** (via survey or extra_vars):

| Var | Example | Required |
|-----|---------|----------|
| `incident_number` | `INC0011410` | yes |
| `host_fqdn` | `ec2-98-83-144-2.compute-1.amazonaws.com` | yes |
| `cve_id` | `CVE-2025-38352` | no (informational) |

**AAP JT**: `Lightspeed Patching - SNow Relate CMDB CI to Incident`
(CaC var: `jt_snow_relate_cmdb`). Uses the ServiceNow credential only — Insights
creds come from env vars injected via a credential type (future) or extra_vars.

## Insights UUID → CMDB correlation_id

The Insights `machine-id` (from `/etc/insights-client/machine-id` on the host)
is stamped into the CMDB CI's `correlation_id` by
`playbooks/servicenow/update_cmdb_correlation_id.yml` (CaC var:
`jt_snow_correlation_id`), so the CI durably links back to its Insights record —
not just into the incident work note. The playbook reads the UUID via SSH
(slurp), so it needs the Linux Machine credential but **not** the Insights API
credentials. It runs in the Provision-and-Onboard workflow after Register RHEL
(parallel to Patch RHEL, terminal leaf).

> The host's OS hostname is set to the public FQDN (`inventory_hostname`) in
> `register_rhel.yml` **before** registration, so the Insights display-name, the
> canonical `fqdn` fact, the AAP inventory name, and the CMDB CI name all agree.

## Key files

| File | Purpose |
|------|---------|
| `playbooks/register_insights.yml` | Installs insights-client, registers with `--display-name` |
| `playbooks/insights_fetch_remediation.yml` | OAuth2 → UUID → confirm `remediation==2` → create remediation plan → download playbook |
| `aap_config/files/controller_credentials.yml` | `cred_insights` — built-in `Insights` (service-account) credential, injects `INSIGHTS_CLIENT_ID/SECRET` env vars |
| `playbooks/servicenow/relate_cmdb_to_incident.yml` | OAuth2 → inventory lookup → CMDB → incident cmdb_ci |
| `playbooks/servicenow/update_cmdb_correlation_id.yml` | SSH → read machine-id → CMDB CI `correlation_id` |
| `aap_config/group_vars/all.yml` | `insights_client_id`, `insights_client_secret`, `insights_base_url` |
| `aap_config/files/controller_job_templates.yml` | `jt_snow_relate_cmdb` JT definition |
| `docs/dev-environment.sh` | `INSIGHTS_CLIENT_ID`, `INSIGHTS_CLIENT_SECRET` (gitignored) |
| `docs/dev-environment.sh.example` | Template with blank Insights vars |

## Notification sweep timing — critical discovery (issue #91)

Red Hat Insights **detects** CVEs on upload (~1 min after `insights-client`
runs) but only **emits** the `new-cve-*` notification on a **server-side daily
sweep** — observed firing at **~03:30 UTC**. There is **no customer API to
trigger it on demand.** Repeated inventory delete/re-register also resets the
per-system "new CVE" baseline, so the sweep may never fire for a staged demo.

This means:
- The CVE appears in the Insights console almost immediately.
- The webhook notification to EDA is delayed 0-24 hours.
- For demos, you **must** self-POST the event (see below).
- For production, the delay is acceptable — the sweep fires daily.

## Self-POST workaround for demos

`playbooks/introduce_cve.yml` works around the sweep delay by self-POSTing:

1. Downgrade a package (default: `openssl`) on the target host.
2. Run `insights-client` so Insights detects the CVE.
3. Poll the Insights vulnerability API until the CVE is visible (up to 5 min).
4. POST a real-shaped vulnerability notification to the EDA event stream.

The POST payload matches `rulebooks/insights_vulnerability_events.yml`
field-for-field (flat envelope: `application`, `event_type`, `context`,
`events[].payload`), so the remediation workflow fires in seconds.

**Env vars needed:**
- `INSIGHTS_EDA_EVENT_STREAM_URL` — the event stream's POST URL (copy from the
  event stream Details page in AAP; per-deployment, not a secret)
- `INSIGHTS_EDA_TOKEN` (fallback: `EDA_EVENT_STREAM_TOKEN`) — the
  `X-Insight-Token` header value (must match the event stream credential)

The **"Forward events to rulebook activation"** toggle on the event stream is
intentionally left **manual** — staging a CVE shouldn't auto-launch
remediation. Flip it ON when you want the POST to drive the workflow.

**Open gap:** The Introduce CVE JT has `cred_linux` + `cred_insights_api`
attached, but neither injects `INSIGHTS_EDA_EVENT_STREAM_URL` or the EDA
token. The self-POST works from a local shell (where `dev-environment.sh` sets
both), but **fails from AAP** because the env vars are empty. Fix = a small
custom credential type injecting those two, attached to the JT.

## Custom Insights API credential type (issue #101, fixes #78)

The built-in **Insights** credential type (kind `insights`) **cannot attach to
job templates** — the controller refuses with *"Cannot assign a Credential of
kind insights"*. It only works on inventories and projects (`scm_type:
insights`).

**Fix:** a custom **`Lightspeed Patching - Insights API`** credential type
(kind `cloud`, attachable to JTs) that injects `INSIGHTS_CLIENT_ID`,
`INSIGHTS_CLIENT_SECRET`, and `INSIGHTS_BASE_URL` as env vars. Defined in
`aap_config/files/controller_credential_types.yml`; the matching credential
instance is `cred_insights_api` in `controller_credentials.yml`.

The built-in `Insights` credential (`cred_insights`) is **retained** for the
future `scm_type: insights` project (Slice 5 — running remediation plans
natively).

## Diagnostic API calls — "no events arrive"

Two console.redhat.com API calls settle the question instantly (use a
service-account bearer token):

```bash
# 1. Did Insights GENERATE a vulnerability notification?
curl -H "Authorization: Bearer $TOKEN" \
  "$INSIGHTS_BASE_URL/api/notifications/v1/notifications/events?bundleIds=<rhel-bundle-id>&includeActions=true"
# Look for application=vulnerability rows. Integration-test clicks do NOT appear here.

# 2. Did it try to DELIVER, and did AAP accept (200) or reject (400)?
curl -H "Authorization: Bearer $TOKEN" \
  "$INSIGHTS_BASE_URL/api/integrations/v1/endpoints/<endpoint-id>/history?includeDetail=true"
```

If (1) shows no vulnerability rows, the daily sweep simply hasn't fired —
that's expected between sweeps and is why we self-POST.

## Gotchas

- **`no_log: true` on the token task** — the client secret is in the request body;
  suppress logging or it appears in AAP job output.
- **Bearer token expires in ~15 minutes** — don't store it across plays; mint a
  fresh one per playbook run.
- **`display_name` filter is case-sensitive and exact-match** — pass the FQDN
  exactly as registered. An EC2 hostname is always lowercase.
- **Host not found (total: 0)** — the host hasn't been registered with Insights
  yet, or was registered under a different display_name (private hostname). Check
  console.redhat.com → Inventory → Systems.
- **Event envelope is flat** — confirmed 2026-06-15. The Insights webhook
  sends `event.payload.application`, `event.payload.event_type`, etc. at the
  top level — **not** nested under `event.payload.data.*`. The rulebook
  conditions and self-POST payload must use the flat structure.
- **Vulnerability API has no `?cve_name=` filter** — the
  `systems/{uuid}/cves` endpoint does not support filtering by CVE name.
  `insights_fetch_remediation.yml` lists up to 100 CVEs and matches
  client-side (hardcoded `limit=100`; a host with >100 CVEs would need
  pagination).
- **Remediation plan name is unique per org** — creating a plan with a
  duplicate name returns `400 SequelizeUniqueConstraintError`.
  `insights_fetch_remediation.yml` tolerates that 400 and looks up the
  existing plan by name (issue #104). Any other 400 still fails loudly.
